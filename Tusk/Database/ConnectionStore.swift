import Foundation

/// Persists connection metadata (no passwords) to disk as JSON.
final class ConnectionStore: Sendable {
    static let shared = ConnectionStore()

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Tusk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("connections.json")
    }()

    private init() {}

    func load() -> [Connection] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Connection].self, from: data)) ?? []
    }

    func save(_ connections: [Connection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
