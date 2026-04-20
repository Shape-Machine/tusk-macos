import Foundation
import Darwin

// MARK: - CloudSQLProxy

/// Manages a `cloud-sql-proxy` child process that forwards a Cloud SQL instance
/// to a local TCP port. Mirrors the structure of SSHTunnel.
actor CloudSQLProxy {
    enum Status: Sendable {
        case starting
        case running
        case crashed(String)
    }

    private(set) var status: Status = .starting
    private(set) var localPort: Int = 0
    /// Last 50 lines of proxy stderr — ring buffer for debugging.
    private(set) var logLines: [String] = []

    private var process: Process?

    // MARK: - Start

    func start(instanceConnectionName: String, useIAMAuth: Bool) async throws -> Int {
        let port = try Self.findFreePort()
        localPort = port

        guard let binary = Self.findBinary("cloud-sql-proxy") else {
            throw CloudSQLProxyError.binaryNotFound
        }

        var args = [instanceConnectionName, "--port", "\(port)"]
        if useIAMAuth { args.append("--auto-iam-authn") }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        // Capture stderr lines into the ring buffer.
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            Task { await self?.appendLines(lines) }
        }

        // Detect unexpected exits while connected.
        proc.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }

        try proc.run()
        process = proc

        // Poll until the proxy port accepts connections.
        do {
            try await waitForPort(port, timeout: 15)
        } catch {
            // Clear the handler before reading so it doesn't race with availableData.
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            proc.terminate()
            process = nil
            // Use availableData (non-blocking) instead of readDataToEndOfFile() which
            // blocks until EOF and can hang if the process is slow to exit.
            let stderrOutput = String(
                data: stderrPipe.fileHandleForReading.availableData,
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = stderrOutput.isEmpty ? error.localizedDescription : stderrOutput
            throw CloudSQLProxyError.proxyFailed(detail)
        }

        status = .running
        return port
    }

    // MARK: - Stop

    func stop() {
        process?.standardError.flatMap { $0 as? Pipe }?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    // MARK: - Restart

    func restart(instanceConnectionName: String, useIAMAuth: Bool) async throws -> Int {
        stop()
        status = .starting
        logLines = []
        return try await start(instanceConnectionName: instanceConnectionName, useIAMAuth: useIAMAuth)
    }

    // MARK: - Private

    private func appendLines(_ lines: [String]) {
        logLines.append(contentsOf: lines)
        if logLines.count > 50 { logLines.removeFirst(logLines.count - 50) }
    }

    private func handleTermination() {
        guard case .running = status else { return }
        let lastLog = logLines.last ?? "Proxy exited unexpectedly."
        status = .crashed(lastLog)
    }

    private func waitForPort(_ port: Int, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Self.isPortOpen(port) { return }
            if let p = process, !p.isRunning {
                throw CloudSQLProxyError.proxyFailed("cloud-sql-proxy exited (code \(p.terminationStatus))")
            }
            try await Task.sleep(nanoseconds: 200_000_000) // 200 ms
        }
        throw CloudSQLProxyError.timeout
    }

    // MARK: - Static helpers

    static func isPortOpen(_ port: Int) -> Bool {
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

    static func findFreePort() throws -> Int {
        var addr           = sockaddr_in()
        addr.sin_family    = sa_family_t(AF_INET)
        addr.sin_port      = 0
        addr.sin_addr      = in_addr(s_addr: INADDR_ANY)

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CloudSQLProxyError.portUnavailable }
        defer { close(fd) }

        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw CloudSQLProxyError.portUnavailable }

        var filled = sockaddr_in()
        var len    = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &filled) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        return Int(filled.sin_port.bigEndian)
    }

    /// Search common Homebrew / system locations then fall back to `which`.
    static func findBinary(_ name: String) -> String? {
        let candidates = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/opt/homebrew/sbin/\(name)",
            "/usr/bin/\(name)",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        // Last resort: ask the shell's PATH via `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    // MARK: - ADC token

    /// Runs `gcloud auth print-access-token` synchronously and returns the token.
    /// Call from a detached task to avoid blocking the main actor.
    static func fetchADCToken() throws -> String {
        guard let gcloud = findBinary("gcloud") else {
            throw CloudSQLProxyError.gcloudNotFound
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: gcloud)
        proc.arguments     = ["auth", "print-access-token"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw CloudSQLProxyError.adcNotConfigured
        }
        let token = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { throw CloudSQLProxyError.adcNotConfigured }
        return token
    }
}

// MARK: - CloudSQLProxyError

enum CloudSQLProxyError: LocalizedError {
    case binaryNotFound
    case portUnavailable
    case timeout
    case proxyFailed(String)
    case gcloudNotFound
    case adcNotConfigured

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "cloud-sql-proxy not found. Install it with: brew install cloud-sql-proxy"
        case .portUnavailable:
            return "Could not allocate a free local port for the Cloud SQL proxy."
        case .timeout:
            return "cloud-sql-proxy did not become ready within 15 seconds. Check the instance connection name and your GCP credentials."
        case .proxyFailed(let detail):
            return "cloud-sql-proxy failed to start: \(detail)"
        case .gcloudNotFound:
            return "gcloud not found. Install Google Cloud SDK from cloud.google.com/sdk."
        case .adcNotConfigured:
            return "Application Default Credentials not configured. Run: gcloud auth application-default login"
        }
    }
}
