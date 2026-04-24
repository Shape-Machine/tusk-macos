import Foundation
import SwiftUI

// MARK: - ConnectionType

enum ConnectionType: String, Codable, CaseIterable, Sendable {
    case direct
    case cloudSQL
}

// MARK: - Connection

struct Connection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 5432
    var database: String
    var username: String
    var useSSL: Bool = false
    var verifySSLCertificate: Bool = false
    var isReadOnly: Bool = false
    var color: ConnectionColor = .blue
    var groupLabel: String = ""
    var notes: String = ""

    // SSH tunnel
    var sshEnabled: Bool = false
    var sshHost: String = ""
    var sshPort: Int = 22
    var sshUser: String = ""
    var sshKeyPath: String = ""

    // Google Cloud SQL
    var connectionType: ConnectionType = .direct
    var cloudSQLInstanceConnectionName: String = ""
    var cloudSQLProject: String = ""   // display only (e.g. "my-project")
    var useADC: Bool = false           // use Application Default Credentials instead of a password

    // Password is NOT stored here — lives in Keychain only.

    var displayHost: String {
        connectionType == .cloudSQL ? cloudSQLInstanceConnectionName : "\(host):\(port)"
    }
}

extension Connection {
    // Custom decoder so that fields added after v1 (groupLabel, notes, SSH fields, etc.)
    // fall back to their defaults when loading older saved JSON that lacks those keys.
    // Defined in an extension so Swift still synthesizes the memberwise initializer.
    init(from decoder: any Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(UUID.self,   forKey: .id)          ?? UUID()
        name        = try c.decode(String.self,           forKey: .name)
        host        = try c.decode(String.self,           forKey: .host)
        port        = try c.decodeIfPresent(Int.self,     forKey: .port)        ?? 5432
        database    = try c.decode(String.self,           forKey: .database)
        username    = try c.decode(String.self,           forKey: .username)
        useSSL                = try c.decodeIfPresent(Bool.self,    forKey: .useSSL)               ?? false
        verifySSLCertificate  = try c.decodeIfPresent(Bool.self,    forKey: .verifySSLCertificate) ?? false
        isReadOnly            = try c.decodeIfPresent(Bool.self,    forKey: .isReadOnly)           ?? false
        color       = try c.decodeIfPresent(ConnectionColor.self, forKey: .color) ?? .blue
        groupLabel  = try c.decodeIfPresent(String.self,  forKey: .groupLabel)  ?? ""
        notes       = try c.decodeIfPresent(String.self,  forKey: .notes)       ?? ""
        sshEnabled  = try c.decodeIfPresent(Bool.self,    forKey: .sshEnabled)  ?? false
        sshHost     = try c.decodeIfPresent(String.self,  forKey: .sshHost)     ?? ""
        sshPort     = try c.decodeIfPresent(Int.self,     forKey: .sshPort)     ?? 22
        sshUser     = try c.decodeIfPresent(String.self,  forKey: .sshUser)     ?? ""
        sshKeyPath  = try c.decodeIfPresent(String.self,  forKey: .sshKeyPath)  ?? ""
        connectionType                 = try c.decodeIfPresent(ConnectionType.self, forKey: .connectionType)                 ?? .direct
        cloudSQLInstanceConnectionName = try c.decodeIfPresent(String.self,         forKey: .cloudSQLInstanceConnectionName) ?? ""
        cloudSQLProject                = try c.decodeIfPresent(String.self,         forKey: .cloudSQLProject)                ?? ""
        useADC                         = try c.decodeIfPresent(Bool.self,           forKey: .useADC)                         ?? false
    }
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
    let toSchema: String
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

/// Masks plaintext passwords so they never appear in the UI.
/// Covers: PASSWORD 'literal'  PASSWORD $$secret$$  PASSWORD $tag$secret$tag$
func redactSQLForDisplay(_ sql: String) -> String {
    guard sql.localizedCaseInsensitiveContains("password") else { return sql }
    let patterns = [
        #"(?i)\bPASSWORD\s+'[^']*'"#,          // single-quoted:  PASSWORD 'secret'
        #"(?i)\bPASSWORD\s+(\$[^$]*\$).*?\1"#, // dollar-quoted:  PASSWORD $$secret$$
    ]
    var result = sql
    for pattern in patterns {
        result = result.replacingOccurrences(of: pattern, with: "PASSWORD '***'", options: .regularExpression)
    }
    return result
}

struct ActivityEntry: Identifiable, Sendable {
    let pid: Int
    var id: Int { pid }
    let applicationName: String
    let state: String           // active, idle, idle in transaction, …
    let query: String
    /// SQL with passwords redacted — computed once at init, used by the UI.
    let displayQuery: String
    let durationSeconds: Int?   // nil when query_start is NULL
    let waitEventType: String?
    let waitEvent: String?

    init(pid: Int, applicationName: String, state: String, query: String,
         durationSeconds: Int?, waitEventType: String?, waitEvent: String?) {
        self.pid = pid
        self.applicationName = applicationName
        self.state = state
        self.query = query
        self.displayQuery = query.isEmpty ? "—" : redactSQLForDisplay(query)
        self.durationSeconds = durationSeconds
        self.waitEventType = waitEventType
        self.waitEvent = waitEvent
    }
}

// MARK: - Table size info

struct TableSizeInfo: Sendable {
    let schema: String
    let name: String
    let totalSize: String       // pg_size_pretty formatted
    let rowEstimate: Int        // n_live_tup
    let indexSize: String       // pg_size_pretty formatted
}
