import Foundation
import Darwin

/// Manages a local SSH port-forward tunnel.
/// Spawns `ssh -N -L localPort:dbHost:dbPort user@sshHost -i keyPath`
/// and polls until the forwarded port is accepting connections.
actor SSHTunnel {
    private var process: Process?
    private(set) var localPort: Int = 0

    // MARK: - Start

    func start(connection: Connection, passphrase: String?) async throws {
        localPort = try Self.findFreePort()

        // Write a temp askpass script if a passphrase is needed.
        // SSH calls it when prompted for the key passphrase.
        var askpassURL: URL? = nil
        if let passphrase, !passphrase.isEmpty {
            askpassURL = try Self.writeAskpassScript(passphrase: passphrase)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = [
            "-N",
            "-L", "\(localPort):\(connection.host):\(connection.port)",
            "-p", "\(connection.sshPort)",
            "-i", connection.sshKeyPath,
            "-o", "StrictHostKeyChecking=no",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=\(passphrase == nil || passphrase!.isEmpty ? "yes" : "no")",
            "-o", "ServerAliveInterval=30",
            "\(connection.sshUser)@\(connection.sshHost)"
        ]

        var env = ProcessInfo.processInfo.environment
        if let url = askpassURL {
            env["SSH_ASKPASS"]         = url.path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"]             = ":0"
        }
        p.environment    = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice

        try p.run()
        process = p

        // Wait for the tunnel to be ready, then clean up the askpass script.
        // By the time the port is open, SSH has already authenticated.
        do {
            try await waitForPort(localPort, timeout: 15)
        } catch {
            p.terminate()
            process = nil
            if let url = askpassURL { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        if let url = askpassURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Stop

    func stop() {
        process?.terminate()
        process = nil
    }

    // MARK: - Free port

    private static func findFreePort() throws -> Int {
        var addr = sockaddr_in()
        addr.sin_family    = sa_family_t(AF_INET)
        addr.sin_port      = 0
        addr.sin_addr      = in_addr(s_addr: INADDR_ANY)

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TuskError.sshTunnelFailed("Could not create socket") }
        defer { close(fd) }

        let bindResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw TuskError.sshTunnelFailed("Could not bind to a free port") }

        var bound = sockaddr_in()
        var len   = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        return Int(bound.sin_port.bigEndian)
    }

    // MARK: - Askpass script

    private static func writeAskpassScript(passphrase: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tusk-askpass-\(UUID().uuidString).sh")
        // Single-quoted passphrase with internal single-quotes escaped
        let escaped = passphrase.replacingOccurrences(of: "'", with: "'\\''")
        let script  = "#!/bin/sh\necho '\(escaped)'\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }

    // MARK: - Port readiness polling

    private func waitForPort(_ port: Int, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Self.isPortOpen(port) { return }
            try await Task.sleep(nanoseconds: 200_000_000) // 200 ms
        }
        throw TuskError.sshTunnelFailed("Timed out waiting for SSH tunnel on port \(port)")
    }

    private static func isPortOpen(_ port: Int) -> Bool {
        var addr        = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(port).bigEndian
        addr.sin_addr   = in_addr(s_addr: inet_addr("127.0.0.1"))

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
