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
            let type: TableInfo.TableType = rawType == "VIEW" ? .view : (rawType == "BASE TABLE" ? .table : .other)
            return TableInfo(schema: schema, name: name, type: type)
        }
    }

    func columns(schema: String, table: String) async throws -> [ColumnInfo] {
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
                  AND tc.table_schema = '\(schema)'
                  AND tc.table_name   = '\(table)'
            ) pk ON c.column_name = pk.column_name
            WHERE c.table_schema = '\(schema)' AND c.table_name = '\(table)'
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
              AND tc.table_schema = '\(schema)'
              AND tc.table_name   = '\(table)'
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
        let result = try await query("""
            SELECT
                tc.constraint_name,
                tc.table_name   AS from_table,
                kcu.column_name AS from_column,
                ccu.column_name AS to_column
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
              ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
              ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND ccu.table_schema = '\(schema)'
              AND ccu.table_name   = '\(table)'
            ORDER BY tc.table_name
            """)

        return result.rows.map { row in
            IncomingReference(
                constraintName: row[safe: 0]?.displayValue ?? "",
                fromTable:      row[safe: 1]?.displayValue ?? "",
                fromColumn:     row[safe: 2]?.displayValue ?? "",
                toColumn:       row[safe: 3]?.displayValue ?? ""
            )
        }
    }

    // MARK: - Raw query

    func query(_ sql: String) async throws -> QueryResult {
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
                return .text(pgCellString(bytes: bytes, dataType: cell.dataType))
            }
            rows.append(cells)
        }

        let duration = Date().timeIntervalSince(start)
        return QueryResult(columns: columns, rows: rows, rowsAffected: rows.count, duration: duration)
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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
        var s = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                       c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
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
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)

    case .time:
        guard let us = buf.readInteger(as: Int64.self) else { break }
        return pgTimeOfDayString(microseconds: us)

    case .timetz:
        // 8 bytes microseconds since midnight + 4 bytes timezone offset (seconds west of UTC)
        guard let us     = buf.readInteger(as: Int64.self),
              let tzSec  = buf.readInteger(as: Int32.self) else { break }
        let absOff = abs(Int(tzSec))
        let sign   = tzSec <= 0 ? "+" : "-"
        return String(format: "%@%@%02d:%02d",
                      pgTimeOfDayString(microseconds: us), sign,
                      absOff / 3600, (absOff % 3600) / 60)

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
        let absMicros = abs(us)
        let h = absMicros / 3_600_000_000
        let m = (absMicros % 3_600_000_000) / 60_000_000
        let s = (absMicros % 60_000_000) / 1_000_000
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
