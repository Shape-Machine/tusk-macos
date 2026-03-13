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

    // MARK: - SSH tunnels (one per tunnelled connection)
    var tunnels: [UUID: SSHTunnel] = [:]

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
        KeychainManager.shared.deletePassword(for: connection.id)
        KeychainManager.shared.deleteSshPassphrase(for: connection.id)
        ConnectionStore.shared.save(connections)
    }

    // MARK: - Connect / Disconnect

    func connect(_ connection: Connection) async throws {
        // Tear down any existing client/tunnel first.
        if let existing = clients.removeValue(forKey: connection.id) {
            await existing.disconnect()
        }
        if let existingTunnel = tunnels.removeValue(forKey: connection.id) {
            await existingTunnel.stop()
        }

        // Start SSH tunnel if enabled; the tunnel exposes a local port that
        // PostgresNIO will connect to instead of the real host/port.
        var effectiveConnection = connection
        if connection.sshEnabled {
            let passphrase = KeychainManager.shared.sshPassphrase(for: connection.id)
            let tunnel = SSHTunnel()
            try await tunnel.start(connection: connection, passphrase: passphrase)
            tunnels[connection.id] = tunnel
            let localPort = await tunnel.localPort
            effectiveConnection.host = "127.0.0.1"
            effectiveConnection.port = localPort
        }

        let password = KeychainManager.shared.password(for: connection.id) ?? ""
        let client = DatabaseClient()
        do {
            try await client.connect(to: effectiveConnection, password: password)
        } catch {
            await client.disconnect()
            if let tunnel = tunnels.removeValue(forKey: connection.id) {
                await tunnel.stop()
            }
            throw error
        }
        clients[connection.id] = client
        selectedConnectionID = connection.id
        try await refreshSchema(for: connection)
    }

    func disconnect(_ connection: Connection) {
        let client = clients.removeValue(forKey: connection.id)
        Task { await client?.disconnect() }
        if let tunnel = tunnels.removeValue(forKey: connection.id) {
            Task { await tunnel.stop() }
        }
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
}

// MARK: - Query tab model

struct QueryTab: Identifiable {
    let id = UUID()
    let connectionID: UUID
    let connectionName: String
    var title: String = "Query"
    var sql: String = ""
}
