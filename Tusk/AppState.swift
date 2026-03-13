import SwiftUI

/// Central app state — drives the entire UI.
@MainActor
@Observable
final class AppState {
    // MARK: - Connections
    var connections: [Connection] = []
    var selectedConnectionID: UUID? = nil

    // MARK: - Active DB clients (one per open connection)
    var clients: [UUID: DatabaseClient] = [:]

    // MARK: - Sidebar selection
    var selectedSidebarItem: SidebarItem? = nil

    // MARK: - Query tabs
    var queryTabs: [QueryTab] = []
    var activeTabID: UUID? = nil

    // MARK: - Schema cache  (connectionID → tables)
    var schemaTables: [UUID: [TableInfo]] = [:]

    // MARK: - UI state
    var isAddingConnection = false
    var editingConnection: Connection? = nil

    init() {
        connections = ConnectionStore.shared.load()
    }

    // MARK: - Connection management

    func addConnection(_ connection: Connection) {
        connections.append(connection)
        ConnectionStore.shared.save(connections)
    }

    func updateConnection(_ connection: Connection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        ConnectionStore.shared.save(connections)
        // Reconnect if this connection is currently active
        if isConnected(connection) {
            Task {
                do { try await connect(connection) }
                catch { print("Reconnect failed: \(error)") }
            }
        }
    }

    func removeConnection(_ connection: Connection) {
        disconnect(connection)
        connections.removeAll { $0.id == connection.id }
        ConnectionStore.shared.save(connections)
    }

    // MARK: - Connect / Disconnect

    func connect(_ connection: Connection) async throws {
        // Disconnect any existing client first — prevents releasing a live
        // PostgresConnection when we overwrite the clients dictionary entry.
        if let existing = clients.removeValue(forKey: connection.id) {
            await existing.disconnect()
        }

        let password = KeychainManager.shared.password(for: connection.id) ?? ""
        let client = DatabaseClient()
        do {
            try await client.connect(to: connection, password: password)
        } catch {
            // Clean up the client before it goes out of scope and is released
            // on the main thread with a live PostgresConnection inside.
            await client.disconnect()
            throw error
        }
        clients[connection.id] = client
        selectedConnectionID = connection.id
        try await refreshSchema(for: connection)
    }

    func disconnect(_ connection: Connection) {
        let client = clients.removeValue(forKey: connection.id)
        Task { await client?.disconnect() }
        schemaTables.removeValue(forKey: connection.id)
        if selectedConnectionID == connection.id {
            selectedConnectionID = nil
            selectedSidebarItem = nil
        }
    }

    func isConnected(_ connection: Connection) -> Bool {
        clients[connection.id] != nil
    }

    // MARK: - Schema refresh

    func refreshSchema(for connection: Connection) async throws {
        guard let client = clients[connection.id] else { return }
        let tables = try await client.tables()
        schemaTables[connection.id] = tables
    }

    // MARK: - Query tabs

    func openQueryTab(for connection: Connection) {
        let tab = QueryTab(connectionID: connection.id, connectionName: connection.name)
        queryTabs.append(tab)
        activeTabID = tab.id
        selectedSidebarItem = .queryEditor(tab.id)
    }

    func closeTab(_ tabID: UUID) {
        queryTabs.removeAll { $0.id == tabID }
        activeTabID = queryTabs.last?.id
    }

    // MARK: - Convenience

    var selectedConnection: Connection? {
        guard let id = selectedConnectionID else { return nil }
        return connections.first { $0.id == id }
    }

    var activeClient: DatabaseClient? {
        guard let id = selectedConnectionID else { return nil }
        return clients[id]
    }
}

// MARK: - Sidebar item type

enum SidebarItem: Hashable {
    case table(connectionID: UUID, schema: String, tableName: String)
    case queryEditor(UUID)
    case schema(connectionID: UUID)
}

// MARK: - Query tab model

struct QueryTab: Identifiable {
    let id = UUID()
    let connectionID: UUID
    let connectionName: String
    var title: String = "Query"
    var sql: String = ""
}
