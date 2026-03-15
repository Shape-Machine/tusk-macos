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

/// Presents a save panel and writes `result` as CSV.
/// `defaultName` is the pre-filled filename (without extension).
@MainActor
func exportResultAsCSV(_ result: QueryResult, defaultName: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "\(defaultName).csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    var lines = [result.columns.map(\.name).joined(separator: ",")]
    for row in result.rows {
        lines.append(row.map { cell in
            let val = cell.displayValue
            let escaped = val.replacingOccurrences(of: "\"", with: "\"\"")
            return escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"")
                ? "\"\(escaped)\""
                : escaped
        }.joined(separator: ","))
    }
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
    var lines = [columns.map(\.name).joined(separator: ",")]
    for row in rows {
        lines.append(row.map { cell in
            let val = cell.displayValue
            let escaped = val.replacingOccurrences(of: "\"", with: "\"\"")
            return escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"")
                ? "\"\(escaped)\""
                : escaped
        }.joined(separator: ","))
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
}

/// Copies rows as a JSON array of objects to the system clipboard.
@MainActor
func copyRowsAsJSON(columns: [QueryColumn], rows: [[QueryCell]]) {
    let objects: [[String: String]] = rows.map { row in
        var obj: [String: String] = [:]
        for (col, cell) in zip(columns, row) {
            obj[col.name] = cell.displayValue
        }
        return obj
    }
    guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: data, encoding: .utf8) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(str, forType: .string)
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
