import Foundation

// MARK: - PgpassEntry

/// A single parsed entry from a .pgpass file.
struct PgpassEntry {
    let host: String
    let port: Int
    let database: String
    let username: String
    let password: String

    /// A human-readable display name derived from the fields.
    var suggestedName: String {
        "\(username)@\(host):\(port)/\(database)"
    }
}

// MARK: - PgpassImporter

enum PgpassImporter {

    /// Reads the file at `url` and returns all concrete, importable entries.
    /// Lines that are comments (starting with `#`) or that have a wildcard in
    /// any identifying field (host, database, username) are skipped, since they
    /// cannot be turned into a concrete connection.
    static func parse(url: URL) throws -> [PgpassEntry] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return parse(string: contents)
    }

    /// Parses the contents of a .pgpass file from a string.
    static func parse(string: String) -> [PgpassEntry] {
        var entries: [PgpassEntry] = []

        for line in string.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip blank lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let fields = splitPgpassLine(trimmed)
            guard fields.count == 5 else { continue }

            let host     = fields[0]
            let portStr  = fields[1]
            let database = fields[2]
            let username = fields[3]
            let password = fields[4]

            // Skip entries with wildcards in any identifying field — they can't
            // be turned into a concrete connection.
            guard host != "*", database != "*", username != "*" else { continue }

            let port = Int(portStr) ?? 5432

            entries.append(PgpassEntry(
                host:     host,
                port:     port,
                database: database,
                username: username,
                password: password
            ))
        }

        return entries
    }

    // MARK: - Private helpers

    /// Splits a .pgpass line on unescaped `:` delimiters.
    /// The spec allows `\:` and `\\` as escape sequences inside field values.
    private static func splitPgpassLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var escaped = false

        for ch in line {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == ":" {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }

    /// Returns the URL of the default ~/.pgpass file.
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pgpass")
    }
}
