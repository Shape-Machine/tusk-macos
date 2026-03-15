import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Query result

struct QueryResult: Sendable {
    let columns: [QueryColumn]
    let rows: [[QueryCell]]
    let duration: TimeInterval

    var isEmpty: Bool { rows.isEmpty }
}

// MARK: - Column descriptor

struct QueryColumn: Identifiable, Sendable {
    let id: Int   // positional index
    let name: String
    let dataType: String
}

// MARK: - Cell value

enum QueryCell: Sendable {
    case null
    case text(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case bytes(Data)

    var displayValue: String {
        switch self {
        case .null:           return "NULL"
        case .text(let s):    return s
        case .integer(let i): return String(i)
        case .double(let d):  return String(d)
        case .bool(let b):    return b ? "true" : "false"
        case .bytes:          return "<binary>"
        }
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - CSV export

private func csvEscape(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"")
        ? "\"\(escaped)\""
        : escaped
}

private func csvLines(columns: [QueryColumn], rows: [[QueryCell]]) -> [String] {
    var lines = [columns.map { csvEscape($0.name) }.joined(separator: ",")]
    for row in rows {
        lines.append(row.map { csvEscape($0.displayValue) }.joined(separator: ","))
    }
    return lines
}

/// Presents a save panel and writes `result` as CSV.
/// `defaultName` is the pre-filled filename (without extension).
@MainActor
func exportResultAsCSV(_ result: QueryResult, defaultName: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "\(defaultName).csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let lines = csvLines(columns: result.columns, rows: result.rows)
    do {
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    } catch {
        let alert = NSAlert()
        alert.messageText = "Export Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - Clipboard copy helpers

/// Copies rows as CSV (header + data) to the system clipboard.
@MainActor
func copyRowsAsCSV(columns: [QueryColumn], rows: [[QueryCell]]) {
    let lines = csvLines(columns: columns, rows: rows)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
}

/// Copies rows as a JSON array of objects to the system clipboard.
/// Values are serialized with native JSON types: null, number, bool, string.
@MainActor
func copyRowsAsJSON(columns: [QueryColumn], rows: [[QueryCell]]) {
    let objects: [[String: Any]] = rows.map { row in
        var obj: [String: Any] = [:]
        for (col, cell) in zip(columns, row) {
            switch cell {
            case .null:             obj[col.name] = NSNull()
            case .integer(let i):  obj[col.name] = NSNumber(value: i)
            case .double(let d):   obj[col.name] = NSNumber(value: d)
            case .bool(let b):     obj[col.name] = b
            case .text(let s):     obj[col.name] = s
            case .bytes(let data): obj[col.name] = data.base64EncodedString()
            }
        }
        return obj
    }
    guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: data, encoding: .utf8) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(str, forType: .string)
}

// MARK: - INSERT copy helpers

private func quoteIdentifier(_ name: String) -> String {
    "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

private func sqlLiteral(_ cell: QueryCell) -> String {
    switch cell {
    case .null:             return "NULL"
    case .text(let s):      return "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    case .integer(let i):   return String(i)
    case .double(let d):    return String(d)
    case .bool(let b):      return b ? "TRUE" : "FALSE"
    case .bytes(let data):  return "'" + data.map { String(format: "\\x%02x", $0) }.joined() + "'"
    }
}

private func insertStatement(schema: String, table: String, columns: [QueryColumn], row: [QueryCell]) -> String {
    let cols = columns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
    let vals = row.map { sqlLiteral($0) }.joined(separator: ", ")
    return "INSERT INTO \(quoteIdentifier(schema)).\(quoteIdentifier(table)) (\(cols)) VALUES (\(vals));"
}

/// Copies a single row as a PostgreSQL INSERT statement to the clipboard.
@MainActor
func copyRowAsInsert(schema: String, table: String, columns: [QueryColumn], row: [QueryCell]) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(insertStatement(schema: schema, table: table, columns: columns, row: row), forType: .string)
}

/// Copies all rows as PostgreSQL INSERT statements (one per line) to the clipboard.
@MainActor
func copyRowsAsInsert(schema: String, table: String, columns: [QueryColumn], rows: [[QueryCell]]) {
    let statements = rows.map { insertStatement(schema: schema, table: table, columns: columns, row: $0) }.joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(statements, forType: .string)
}

// MARK: - App-level errors

enum TuskError: LocalizedError {
    case notConnected
    case queryFailed(String)
    case connectionFailed(String)
    case sshTunnelFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:              return "Not connected to a database."
        case .queryFailed(let msg):      return "Query failed: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .sshTunnelFailed(let msg):  return "SSH tunnel failed: \(msg)"
        }
    }
}
