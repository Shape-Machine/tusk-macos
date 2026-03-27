import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

// MARK: - ConnectionBox
//
// PostgresNIO asserts that PostgresConnection is deallocated on its EventLoop
// thread. This wrapper ensures that even if DatabaseClient is released on the
// main thread, the underlying connection is always closed and released on the
// correct EventLoop thread via deinit.
private final class ConnectionBox: @unchecked Sendable {
    let connection: PostgresConnection
    private let eventLoop: any EventLoop

    init(_ connection: PostgresConnection, on eventLoop: any EventLoop) {
        self.connection = connection
        self.eventLoop = eventLoop
    }

    deinit {
        // Schedule close on the EventLoop so PostgresConnection.deinit fires
        // on the right thread — safe even if already closed.
        // Explicit type forces the EventLoopFuture overload (not async throws).
        let conn = connection
        eventLoop.execute { let _: EventLoopFuture<Void> = conn.close() }
    }
}

// MARK: - DatabaseClient

/// Manages a single PostgreSQL connection.
/// Runs on its own actor to keep DB work off the main thread.
actor DatabaseClient {
    private var box: ConnectionBox?
    private let logger = Logger(label: "tusk.database")

    // MARK: - Connect / Disconnect

    func connect(to info: Connection, password: String) async throws {
        let el = MultiThreadedEventLoopGroup.singleton.next()

        let tlsConfig: PostgresConnection.Configuration.TLS
        if info.useSSL {
            tlsConfig = .prefer(try NIOSSLContext(configuration: .makeClientConfiguration()))
        } else {
            tlsConfig = .disable
        }

        let config = PostgresConnection.Configuration(
            host: info.host,
            port: info.port,
            username: info.username,
            password: password.isEmpty ? nil : password,
            database: info.database,
            tls: tlsConfig
        )

        let conn = try await PostgresConnection.connect(
            on: el,
            configuration: config,
            id: 1,
            logger: logger
        )
        box = ConnectionBox(conn, on: el)
    }

    func disconnect() async {
        guard let b = box else { return }
        box = nil                          // nil first — deinit won't double-close
        try? await b.connection.close()
    }

    var isConnected: Bool { box != nil }

    // MARK: - Schema queries

    func tables() async throws -> [TableInfo] {
        let result = try await query("""
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
            ORDER BY table_schema, table_name
            """)

        return result.rows.map { row in
            let schema  = row[safe: 0]?.displayValue ?? "public"
            let name    = row[safe: 1]?.displayValue ?? ""
            let rawType = row[safe: 2]?.displayValue ?? ""
            let type: TableInfo.TableType
            switch rawType {
            case "VIEW":       type = .view
            case "BASE TABLE": type = .table
            default:           type = .other
            }
            return TableInfo(schema: schema, name: name, type: type)
        }
    }

    func columns(schema: String, table: String) async throws -> [ColumnInfo] {
        let s = schema.sqlEscaped
        let t = table.sqlEscaped
        let result = try await query("""
            SELECT
                c.column_name,
                c.data_type,
                c.is_nullable,
                c.column_default,
                CASE WHEN pk.column_name IS NOT NULL THEN 'true' ELSE 'false' END AS is_primary_key
            FROM information_schema.columns c
            LEFT JOIN (
                SELECT ku.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage ku
                  ON tc.constraint_name = ku.constraint_name
                 AND tc.table_schema = ku.table_schema
                WHERE tc.constraint_type = 'PRIMARY KEY'
                  AND tc.table_schema = '\(s)'
                  AND tc.table_name   = '\(t)'
            ) pk ON c.column_name = pk.column_name
            WHERE c.table_schema = '\(s)' AND c.table_name = '\(t)'
            ORDER BY c.ordinal_position
            """)

        return result.rows.map { row in
            ColumnInfo(
                name:         row[safe: 0]?.displayValue ?? "",
                dataType:     row[safe: 1]?.displayValue ?? "",
                isNullable:   (row[safe: 2]?.displayValue ?? "YES") == "YES",
                defaultValue: row[safe: 3]?.isNull == true ? nil : row[safe: 3]?.displayValue,
                isPrimaryKey: (row[safe: 4]?.displayValue ?? "false") == "true"
            )
        }
    }

    func foreignKeys(schema: String, table: String) async throws -> [ForeignKeyInfo] {
        let s = schema.sqlEscaped
        let t = table.sqlEscaped
        let result = try await query("""
            SELECT
                tc.constraint_name,
                kcu.column_name,
                ccu.table_name  AS foreign_table,
                ccu.column_name AS foreign_column
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
              ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
              ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_schema = '\(s)'
              AND tc.table_name   = '\(t)'
            """)

        return result.rows.map { row in
            ForeignKeyInfo(
                constraintName: row[safe: 0]?.displayValue ?? "",
                fromColumn:     row[safe: 1]?.displayValue ?? "",
                toTable:        row[safe: 2]?.displayValue ?? "",
                toColumn:       row[safe: 3]?.displayValue ?? ""
            )
        }
    }

    func incomingReferences(schema: String, table: String) async throws -> [IncomingReference] {
        let s = schema.sqlEscaped
        let t = table.sqlEscaped
        let result = try await query("""
            SELECT
                tc.constraint_name,
                tc.table_schema AS from_schema,
                tc.table_name   AS from_table,
                kcu.column_name AS from_column,
                ccu.column_name AS to_column
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
              ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
              ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND ccu.table_schema = '\(s)'
              AND ccu.table_name   = '\(t)'
            ORDER BY tc.table_schema, tc.table_name
            """)

        return result.rows.map { row in
            IncomingReference(
                constraintName: row[safe: 0]?.displayValue ?? "",
                fromSchema:     row[safe: 1]?.displayValue ?? "",
                fromTable:      row[safe: 2]?.displayValue ?? "",
                fromColumn:     row[safe: 3]?.displayValue ?? "",
                toColumn:       row[safe: 4]?.displayValue ?? ""
            )
        }
    }

    func tableDDL(schema: String, table: String) async throws -> String {
        let s = schema.sqlEscaped
        let t = table.sqlEscaped
        let cols = try await query("""
            SELECT
                a.attname,
                pg_catalog.format_type(a.atttypid, a.atttypmod),
                a.attnotnull,
                CASE WHEN ad.adbin IS NOT NULL
                     THEN pg_catalog.pg_get_expr(ad.adbin, ad.adrelid)
                     ELSE NULL END
            FROM pg_catalog.pg_attribute a
            JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_catalog.pg_attrdef ad
              ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
            WHERE n.nspname = '\(s)' AND c.relname = '\(t)'
              AND a.attnum > 0 AND NOT a.attisdropped
            ORDER BY a.attnum
            """)

        let cons = try await query("""
            SELECT pg_catalog.pg_get_constraintdef(con.oid, true)
            FROM pg_catalog.pg_constraint con
            JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = '\(s)' AND c.relname = '\(t)'
            ORDER BY con.contype
            """)

        var lines: [String] = []
        for row in cols.rows {
            let name    = row[safe: 0]?.displayValue ?? ""
            let type    = row[safe: 1]?.displayValue ?? ""
            let notNull = (row[safe: 2]?.displayValue ?? "false") == "true"
            let defVal  = row[safe: 3]?.isNull == true ? nil : row[safe: 3]?.displayValue

            var line = "    \(quoteIdentifier(name)) \(type)"
            if notNull  { line += " NOT NULL" }
            if let d = defVal { line += " DEFAULT \(d)" }
            lines.append(line)
        }
        for row in cons.rows {
            let def = row[safe: 0]?.displayValue ?? ""
            lines.append("    \(def)")
        }

        return "CREATE TABLE \(quoteIdentifier(schema)).\(quoteIdentifier(table)) (\n\(lines.joined(separator: ",\n"))\n);"
    }

    func fetchIndexes(schema: String, table: String) async throws -> [IndexInfo] {
        let s = schema.sqlEscaped
        let t = table.sqlEscaped
        let result = try await query("""
            SELECT pi.indexname, pi.indexdef, ix.indisunique, ix.indisprimary
            FROM pg_indexes pi
            JOIN pg_namespace n ON n.nspname = pi.schemaname
            JOIN pg_class tc ON tc.relname = pi.tablename AND tc.relnamespace = n.oid
            JOIN pg_class ic ON ic.relname = pi.indexname AND ic.relnamespace = n.oid
            JOIN pg_index ix ON ix.indexrelid = ic.oid AND ix.indrelid = tc.oid
            WHERE pi.schemaname = '\(s)' AND pi.tablename = '\(t)'
            ORDER BY pi.indexname
            """)

        return result.rows.map { row in
            IndexInfo(
                name:       row[safe: 0]?.displayValue ?? "",
                definition: row[safe: 1]?.displayValue ?? "",
                isUnique:   (row[safe: 2]?.displayValue ?? "false") == "true",
                isPrimary:  (row[safe: 3]?.displayValue ?? "false") == "true"
            )
        }
    }

    func fetchTriggers(schema: String, table: String) async throws -> [TriggerInfo] {
        let s = schema.sqlEscaped
        let t = table.sqlEscaped
        let result = try await query("""
            SELECT trigger_name, event_manipulation, action_timing, action_statement
            FROM information_schema.triggers
            WHERE trigger_schema = '\(s)' AND event_object_table = '\(t)'
            ORDER BY trigger_name, event_manipulation
            """)

        return result.rows.map { row in
            TriggerInfo(
                name:      row[safe: 0]?.displayValue ?? "",
                event:     row[safe: 1]?.displayValue ?? "",
                timing:    row[safe: 2]?.displayValue ?? "",
                statement: row[safe: 3]?.displayValue ?? ""
            )
        }
    }

    func enums() async throws -> [EnumInfo] {
        let result = try await query("""
            SELECT n.nspname, t.typname, e.enumlabel
            FROM pg_type t
            JOIN pg_enum e ON e.enumtypid = t.oid
            JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
            ORDER BY n.nspname, t.typname, e.enumsortorder
            """)

        var infos: [EnumInfo] = []
        var currentSchema = ""
        var currentName = ""
        var currentValues: [String] = []

        for row in result.rows {
            let schema = row[safe: 0]?.displayValue ?? ""
            let name   = row[safe: 1]?.displayValue ?? ""
            let value  = row[safe: 2]?.displayValue ?? ""
            if schema == currentSchema && name == currentName {
                currentValues.append(value)
            } else {
                if !currentName.isEmpty {
                    infos.append(EnumInfo(schema: currentSchema, name: currentName, values: currentValues))
                }
                currentSchema = schema
                currentName   = name
                currentValues = [value]
            }
        }
        if !currentName.isEmpty {
            infos.append(EnumInfo(schema: currentSchema, name: currentName, values: currentValues))
        }
        return infos
    }

    func sequences() async throws -> [SequenceInfo] {
        let result = try await query("""
            SELECT sequence_schema, sequence_name
            FROM information_schema.sequences
            WHERE sequence_schema NOT IN ('pg_catalog', 'information_schema')
            ORDER BY sequence_schema, sequence_name
            """)

        return result.rows.map { row in
            SequenceInfo(
                schema: row[safe: 0]?.displayValue ?? "",
                name:   row[safe: 1]?.displayValue ?? ""
            )
        }
    }

    func functions() async throws -> [FunctionInfo] {
        let result = try await query("""
            SELECT n.nspname,
                   p.proname,
                   pg_catalog.pg_get_function_arguments(p.oid),
                   CASE p.prokind WHEN 'p' THEN '' ELSE pg_catalog.pg_get_function_result(p.oid) END
            FROM pg_catalog.pg_proc p
            JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
              AND p.prokind IN ('f', 'p')
            ORDER BY n.nspname, p.proname
            """)

        return result.rows.map { row in
            let schema  = row[safe: 0]?.displayValue ?? ""
            let name    = row[safe: 1]?.displayValue ?? ""
            let args    = row[safe: 2]?.displayValue ?? ""
            let ret     = row[safe: 3]?.displayValue ?? ""
            let sig     = ret.isEmpty ? "\(name)(\(args))" : "\(name)(\(args)) → \(ret)"
            return FunctionInfo(schema: schema, name: name, signature: sig)
        }
    }

    // MARK: - Raw query

    func query(_ sql: String, rowLimit: Int? = nil) async throws -> QueryResult {
        guard let conn = box?.connection else { throw TuskError.notConnected }

        let start = Date()
        let pgRows: PostgresRowSequence
        do {
            pgRows = try await conn.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        } catch let psql as PSQLError {
            let msg = psql.serverInfo?[.message]
                ?? psql.serverInfo?[.detail]
                ?? "PSQLError code \(psql.code)"
            throw TuskError.queryFailed(msg)
        }

        var columns: [QueryColumn] = []
        var rows: [[QueryCell]] = []
        var columnsBuilt = false

        for try await pgRow in pgRows {
            if !columnsBuilt {
                columns = pgRow.enumerated().map { index, cell in
                    QueryColumn(id: index, name: cell.columnName, dataType: cell.dataType.description)
                }
                columnsBuilt = true
            }

            let cells: [QueryCell] = pgRow.map { cell in
                guard let bytes = cell.bytes else { return QueryCell.null }
                return pgCellValue(bytes: bytes, dataType: cell.dataType)
            }
            rows.append(cells)
            if let rowLimit, rows.count >= rowLimit { break }
        }

        let duration = Date().timeIntervalSince(start)
        return QueryResult(columns: columns, rows: rows, duration: duration)
    }

    // MARK: - Activity monitor

    func activityMonitor() async throws -> [ActivityEntry] {
        let result = try await query("""
            SELECT pid,
                   application_name,
                   COALESCE(state, ''),
                   COALESCE(query, ''),
                   EXTRACT(EPOCH FROM (now() - query_start))::bigint,
                   wait_event_type,
                   wait_event
            FROM pg_stat_activity
            WHERE pid <> pg_backend_pid()
            ORDER BY query_start NULLS LAST
            """)
        return result.rows.map { row in
            ActivityEntry(
                pid:             { if case .integer(let i) = row[safe: 0] { return Int(i) }; return 0 }(),
                applicationName: row[safe: 1].flatMap { $0.isNull ? nil : $0.displayValue } ?? "",
                state:           row[safe: 2]?.displayValue ?? "",
                query:           row[safe: 3]?.displayValue ?? "",
                durationSeconds: { if case .integer(let i) = row[safe: 4] { return Int(i) }; return nil }(),
                waitEventType:   row[safe: 5].flatMap { $0.isNull ? nil : $0.displayValue },
                waitEvent:       row[safe: 6].flatMap { $0.isNull ? nil : $0.displayValue }
            )
        }
    }

    func cancelBackend(pid: Int) async throws {
        let result = try await query("SELECT pg_cancel_backend(\(pid))")
        guard case .bool(true) = result.rows.first?.first else {
            throw TuskError.queryFailed("pg_cancel_backend returned false — query may have already finished")
        }
    }

    func terminateBackend(pid: Int) async throws {
        let result = try await query("SELECT pg_terminate_backend(\(pid))")
        guard case .bool(true) = result.rows.first?.first else {
            throw TuskError.queryFailed("pg_terminate_backend returned false — backend may have already exited")
        }
    }

    // MARK: - Table sizes

    func tableSizes() async throws -> [TableSizeInfo] {
        let result = try await query("""
            SELECT schemaname,
                   relname,
                   pg_size_pretty(pg_total_relation_size(relid)),
                   n_live_tup,
                   pg_size_pretty(pg_indexes_size(relid))
            FROM pg_stat_user_tables
            ORDER BY schemaname, relname
            """)
        return result.rows.map { row in
            TableSizeInfo(
                schema:      row[safe: 0]?.displayValue ?? "",
                name:        row[safe: 1]?.displayValue ?? "",
                totalSize:   row[safe: 2]?.displayValue ?? "",
                rowEstimate: { if case .integer(let i) = row[safe: 3] { return Int(i) }; return 0 }(),
                indexSize:   row[safe: 4]?.displayValue ?? ""
            )
        }
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - SQL string literal escaping

private extension String {
    /// Escapes a value for embedding inside a SQL single-quoted string literal
    /// by doubling any single quotes, e.g. "user's" → "user''s".
    var sqlEscaped: String { replacingOccurrences(of: "'", with: "''") }
}

// quoteIdentifier is defined in QueryResult.swift (module-wide)

// MARK: - PostgreSQL binary date/time decoding
//
// PostgresNIO requests binary result format via the extended query protocol.
// Date/time values arrive as raw bytes (int64/int32), not UTF-8 strings,
// so getString() returns nil/garbage for those columns.
// We decode the known binary layouts here and fall back to text for all
// other types.

/// 2000-01-01 00:00:00 UTC expressed as a Unix timestamp (seconds).
private let pgEpochOffset: Double = 946_684_800

private let pgUTCTimeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
private let pgUTCCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = pgUTCTimeZone
    return c
}()

/// Returns a typed `QueryCell` for a non-null PostgreSQL cell.
/// Produces `.bool`, `.integer`, or `.double` for the corresponding wire types;
/// falls back to `.text` (via `pgCellString`) for everything else.
private func pgCellValue(bytes: ByteBuffer, dataType: PostgresDataType) -> QueryCell {
    var buf = bytes
    switch dataType {
    case .bool:
        guard let byte = buf.readInteger(as: UInt8.self) else { break }
        return .bool(byte != 0)
    case .int2:
        guard let v = buf.readInteger(as: Int16.self) else { break }
        return .integer(Int64(v))
    case .int4, .oid:
        guard let v = buf.readInteger(as: Int32.self) else { break }
        return .integer(Int64(v))
    case .int8:
        guard let v = buf.readInteger(as: Int64.self) else { break }
        return .integer(v)
    case .float4:
        guard let bits = buf.readInteger(as: UInt32.self) else { break }
        return .double(Double(Float(bitPattern: bits)))
    case .float8:
        guard let bits = buf.readInteger(as: UInt64.self) else { break }
        return .double(Double(bitPattern: bits))
    default:
        break
    }
    return .text(pgCellString(bytes: bytes, dataType: dataType))
}

/// Returns a display string for a single PostgreSQL cell value.
/// Handles binary-encoded numeric, boolean, and date/time types; falls back to UTF-8 text.
private func pgCellString(bytes: ByteBuffer, dataType: PostgresDataType) -> String {
    var buf = bytes
    switch dataType {

    case .bool:
        guard let byte = buf.readInteger(as: UInt8.self) else { break }
        return byte != 0 ? "true" : "false"

    case .int2:
        guard let v = buf.readInteger(as: Int16.self) else { break }
        return String(v)

    case .int4, .oid:
        guard let v = buf.readInteger(as: Int32.self) else { break }
        return String(v)

    case .int8:
        guard let v = buf.readInteger(as: Int64.self) else { break }
        return String(v)

    case .float4:
        guard let bits = buf.readInteger(as: UInt32.self) else { break }
        return String(Float(bitPattern: bits))

    case .float8:
        guard let bits = buf.readInteger(as: UInt64.self) else { break }
        return String(Double(bitPattern: bits))

    case .uuid:
        guard let b = buf.readBytes(length: 16) else { break }
        let t: uuid_t = (b[0],  b[1],  b[2],  b[3],
                         b[4],  b[5],  b[6],  b[7],
                         b[8],  b[9],  b[10], b[11],
                         b[12], b[13], b[14], b[15])
        return UUID(uuid: t).uuidString.lowercased()

    case .timestamp, .timestamptz:
        guard let us = buf.readInteger(as: Int64.self) else { break }
        // Floor-divide so the remainder (micros) is always in [0, 999_999].
        // Swift's % truncates toward zero, giving a negative remainder for
        // negative us — which would produce the wrong fractional digits for
        // timestamps before the PostgreSQL epoch (2000-01-01).
        let (q, r) = us.quotientAndRemainder(dividingBy: 1_000_000)
        let wholeSeconds: Int64 = r < 0 ? q - 1 : q
        let micros:       Int64 = r < 0 ? r + 1_000_000 : r
        let date = Date(timeIntervalSince1970: pgEpochOffset + Double(wholeSeconds))
        let c = pgUTCCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = c.year, let month = c.month, let day = c.day,
              let hour = c.hour, let minute = c.minute, let second = c.second else { break }
        var s = String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
        if micros != 0 {
            var f = String(format: "%06d", micros)
            while f.hasSuffix("0") { f.removeLast() }
            s += "." + f
        }
        return s

    case .date:
        guard let days = buf.readInteger(as: Int32.self) else { break }
        let date = Date(timeIntervalSince1970: pgEpochOffset + Double(days) * 86_400)
        let c = pgUTCCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { break }
        return String(format: "%04d-%02d-%02d", year, month, day)

    case .time:
        guard let us = buf.readInteger(as: Int64.self) else { break }
        return pgTimeOfDayString(microseconds: us)

    case .timetz:
        // 8 bytes microseconds since midnight + 4 bytes timezone offset (seconds west of UTC)
        guard let us     = buf.readInteger(as: Int64.self),
              let tzSec  = buf.readInteger(as: Int32.self) else { break }
        let absOff  = abs(Int(tzSec))
        let sign    = tzSec <= 0 ? "+" : "-"
        let tzHH    = absOff / 3600
        let tzMM    = (absOff % 3600) / 60
        let tzSS    = absOff % 60
        let tzStr   = tzSS != 0
            ? String(format: "%02d:%02d:%02d", tzHH, tzMM, tzSS)
            : String(format: "%02d:%02d", tzHH, tzMM)
        return "\(pgTimeOfDayString(microseconds: us))\(sign)\(tzStr)"

    case .interval:
        // 8 bytes microseconds + 4 bytes days + 4 bytes months
        guard let us     = buf.readInteger(as: Int64.self),
              let days   = buf.readInteger(as: Int32.self),
              let months = buf.readInteger(as: Int32.self) else { break }
        var parts: [String] = []
        let years = months / 12
        let mons  = months % 12
        if years != 0 { parts.append("\(years) \(years == 1 ? "year" : "years")") }
        if mons  != 0 { parts.append("\(mons) \(mons == 1 ? "month" : "months")") }
        if days  != 0 { parts.append("\(days) \(days == 1 ? "day" : "days")") }
        // Use magnitude (UInt64) to avoid overflow trap when us == Int64.min.
        let absMicros: UInt64 = us.magnitude
        let h    = absMicros / 3_600_000_000
        let m    = (absMicros % 3_600_000_000) / 60_000_000
        let s    = (absMicros % 60_000_000)    / 1_000_000
        let frac = absMicros % 1_000_000
        var timeStr = String(format: "%02d:%02d:%02d", h, m, s)
        if frac != 0 {
            var f = String(format: "%06d", frac)
            while f.hasSuffix("0") { f.removeLast() }
            timeStr += "." + f
        }
        if us < 0 { timeStr = "-" + timeStr }
        if us != 0 || parts.isEmpty { parts.append(timeStr) }
        return parts.joined(separator: " ")

    default:
        break
    }

    // Remaining types (text, varchar, json, numeric, …): UTF-8 text from the server
    return bytes.getString(at: bytes.readerIndex, length: bytes.readableBytes) ?? ""
}

/// Formats microseconds-since-midnight as `HH:MM:SS[.ffffff]`.
private func pgTimeOfDayString(microseconds us: Int64) -> String {
    let h    = us / 3_600_000_000
    let m    = (us % 3_600_000_000) / 60_000_000
    let s    = (us % 60_000_000)    / 1_000_000
    let frac = us % 1_000_000
    var str  = String(format: "%02d:%02d:%02d", h, m, s)
    if frac != 0 {
        var f = String(format: "%06d", frac)
        while f.hasSuffix("0") { f.removeLast() }
        str += "." + f
    }
    return str
}
