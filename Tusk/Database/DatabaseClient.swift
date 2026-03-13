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
        let pgRows = try await conn.query(PostgresQuery(unsafeSQL: sql), logger: logger)

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
                return .text(bytes.getString(at: bytes.readerIndex, length: bytes.readableBytes) ?? "")
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
