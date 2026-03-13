import Foundation

// MARK: - Query result

struct QueryResult: Sendable {
    let columns: [QueryColumn]
    let rows: [[QueryCell]]
    let rowsAffected: Int
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

// MARK: - App-level errors

enum TuskError: LocalizedError {
    case notConnected
    case queryFailed(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:              return "Not connected to a database."
        case .queryFailed(let msg):      return "Query failed: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        }
    }
}
