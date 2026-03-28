import Foundation
import SwiftUI

// MARK: - Connection

struct Connection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 5432
    var database: String
    var username: String
    var useSSL: Bool = false
    var color: ConnectionColor = .blue
    var groupLabel: String = ""
    var notes: String = ""

    // SSH tunnel
    var sshEnabled: Bool = false
    var sshHost: String = ""
    var sshPort: Int = 22
    var sshUser: String = ""
    var sshKeyPath: String = ""

    // Password is NOT stored here — lives in Keychain only.

    var displayHost: String { "\(host):\(port)" }
}

// MARK: - Connection color (for visual tagging)

enum ConnectionColor: String, Codable, CaseIterable, Sendable {
    case blue, green, orange, red, purple, gray

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .gray:   return .secondary
        }
    }
}

// MARK: - Table info (from information_schema)

struct TableInfo: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(schema).\(name)" }
    let schema: String
    let name: String
    let type: TableType

    enum TableType: String, Sendable {
        case table = "BASE TABLE"
        case view  = "VIEW"
        case other
    }
}

// MARK: - Column info

struct ColumnInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let dataType: String
    let isNullable: Bool
    let defaultValue: String?
    let isPrimaryKey: Bool
}

// MARK: - Index info

struct IndexInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let definition: String
    let isUnique: Bool
    let isPrimary: Bool
}

// MARK: - Trigger info

struct TriggerInfo: Identifiable, Sendable {
    var id: String { "\(name)-\(event)" }
    let name: String
    let event: String    // INSERT, UPDATE, DELETE
    let timing: String   // BEFORE, AFTER, INSTEAD OF
    let statement: String
}

// MARK: - Foreign key info

struct ForeignKeyInfo: Identifiable, Sendable {
    var id: String { constraintName }
    let constraintName: String
    let fromColumn: String
    let toTable: String
    let toColumn: String
}

// MARK: - Incoming FK reference (another table's FK points to this table)

struct IncomingReference: Identifiable, Sendable {
    var id: String { constraintName }
    let constraintName: String
    let fromSchema: String  // schema that owns the FK table
    let fromTable: String   // the table that owns the FK
    let fromColumn: String  // the FK column in that table
    let toColumn: String    // the referenced column in the focal table
}

// MARK: - Full table schema

struct TableSchema: Sendable {
    let table: TableInfo
    var columns: [ColumnInfo] = []
    var indexes: [IndexInfo] = []
    var foreignKeys: [ForeignKeyInfo] = []
}

// MARK: - Activity monitor entry

struct ActivityEntry: Identifiable, Sendable {
    let pid: Int
    var id: Int { pid }
    let applicationName: String
    let state: String           // active, idle, idle in transaction, …
    let query: String
    let durationSeconds: Int?   // nil when query_start is NULL
    let waitEventType: String?
    let waitEvent: String?
}

// MARK: - Table size info

struct TableSizeInfo: Sendable {
    let schema: String
    let name: String
    let totalSize: String       // pg_size_pretty formatted
    let rowEstimate: Int        // n_live_tup
    let indexSize: String       // pg_size_pretty formatted
}
