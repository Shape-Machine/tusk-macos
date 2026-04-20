import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Query result

struct QueryResult: Sendable {
    let id: UUID = UUID()
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

func quoteIdentifier(_ name: String) -> String {
    "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

func quoteLiteral(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
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

// MARK: - Multi-statement execution

struct ExecutionEntry: Identifiable, Sendable {
    let id: UUID = UUID()
    let index: Int      // 1-based
    let sql: String     // trimmed statement text

    enum Outcome: Sendable {
        case running
        case rows(QueryResult, isCapped: Bool)
        case ok(duration: TimeInterval)     // DML/DDL — no result set
        case error(String)
        case explain(ExplainResult)
        case cancelled
    }

    var outcome: Outcome = .running
}

// MARK: - Explain plan models

struct ExplainNode: Sendable {
    let nodeType: String
    let relationName: String?
    let indexName: String?
    let alias: String?
    let startupCost: Double
    let totalCost: Double
    let planRows: Int
    let planWidth: Int
    // Populated only when ANALYZE is used
    let actualStartupTime: Double?
    let actualTotalTime: Double?
    let actualRows: Int?
    let actualLoops: Int?
    let children: [ExplainNode]

    var isSeqScan: Bool { nodeType == "Seq Scan" }

    /// Parse from the dictionary produced by JSONSerialization on Postgres EXPLAIN FORMAT JSON output.
    static func parse(_ d: [String: Any]) -> ExplainNode {
        let children = (d["Plans"] as? [[String: Any]] ?? []).map { parse($0) }
        return ExplainNode(
            nodeType:           d["Node Type"]          as? String ?? "?",
            relationName:       d["Relation Name"]      as? String,
            indexName:          d["Index Name"]         as? String,
            alias:              d["Alias"]              as? String,
            startupCost:        d["Startup Cost"]       as? Double ?? 0,
            totalCost:          d["Total Cost"]         as? Double ?? 0,
            planRows:           d["Plan Rows"]          as? Int    ?? 0,
            planWidth:          d["Plan Width"]         as? Int    ?? 0,
            actualStartupTime:  d["Actual Startup Time"] as? Double,
            actualTotalTime:    d["Actual Total Time"]   as? Double,
            actualRows:         d["Actual Rows"]         as? Int,
            actualLoops:        d["Actual Loops"]        as? Int,
            children:           children
        )
    }
}

struct ExplainResult: Sendable {
    let plan: ExplainNode
    let planningMs: Double?
    let executionMs: Double?
    let duration: TimeInterval   // wall-clock time of the EXPLAIN query itself

    static func parse(jsonText: String, duration: TimeInterval) -> ExplainResult? {
        guard let data = jsonText.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = top.first,
              let planDict = first["Plan"] as? [String: Any]
        else { return nil }
        return ExplainResult(
            plan:        ExplainNode.parse(planDict),
            planningMs:  first["Planning Time"]  as? Double,
            executionMs: first["Execution Time"] as? Double,
            duration:    duration
        )
    }
}

// MARK: - Schema object models

struct EnumInfo: Identifiable, Sendable {
    var id: String { "\(schema).\(name)" }
    let schema: String
    let name: String
    let values: [String]
}

struct SequenceInfo: Identifiable, Sendable {
    var id: String { "\(schema).\(name)" }
    let schema: String
    let name: String
}

struct FunctionInfo: Identifiable, Sendable {
    var id: String { "\(schema).\(signature)" }
    let schema: String
    let name: String
    let signature: String       // e.g. "my_func(integer, text) → boolean"
    let oid: UInt32             // pg_proc.oid — used for pg_get_functiondef
    let identityArgs: String    // pg_get_function_identity_arguments — used for DROP FUNCTION
}

// MARK: - Sequence detail (fetched on demand)

struct SequenceDetail: Sendable {
    let schema: String
    let name: String
    let dataType: String
    let startValue: Int64
    let minValue: Int64
    let maxValue: Int64
    let increment: Int64
    let cycleOption: Bool
    let lastValue: Int64?       // nil if the sequence has never been used
    let ownedByTable: String?   // "schema.table" if owned by a serial column
    let ownedByColumn: String?
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
