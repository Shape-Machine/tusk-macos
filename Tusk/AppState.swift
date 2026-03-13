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

    // MARK: - Detail tabs (one per open table or query editor)
    var openTabs: [DetailTab] = []
    var activeDetailTabID: UUID? = nil

    // MARK: - Query tabs (stores editor state; paired with a DetailTab)
    var queryTabs: [QueryTab] = []

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

        // Close all detail tabs belonging to this connection
        let tabsToClose = openTabs.filter { tab in
            switch tab.kind {
            case .table(let cid, _, _): return cid == connection.id
            case .queryEditor(let qid):
                return queryTabs.first(where: { $0.id == qid })?.connectionID == connection.id
            }
        }
        for tab in tabsToClose { closeDetailTab(tab.id) }

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

    func openOrActivateTableTab(connectionID: UUID, schema: String, tableName: String) {
        if let existing = openTabs.first(where: {
            if case .table(let cid, let s, let n) = $0.kind {
                return cid == connectionID && s == schema && n == tableName
            }
            return false
        }) {
            activateDetailTab(existing)
            return
        }
        let tab = DetailTab(
            id: UUID(),
            title: tableName,
            icon: "tablecells",
            kind: .table(connectionID: connectionID, schema: schema, tableName: tableName)
        )
        openTabs.append(tab)
        activateDetailTab(tab)
    }

    func openFileInEditor(url: URL) {
        let connID = selectedConnectionID
        let connName = connID.flatMap { id in connections.first(where: { $0.id == id }) }?.name ?? ""

        let sql = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var queryTab = QueryTab()
        queryTab.connectionID = connID
        queryTab.connectionName = connName
        queryTab.title = url.deletingPathExtension().lastPathComponent
        queryTab.sql = sql
        queryTab.sourceURL = url
        queryTabs.append(queryTab)

        let detailTab = DetailTab(
            id: UUID(),
            title: queryTab.title,
            icon: "doc.text",
            kind: .queryEditor(queryTabID: queryTab.id)
        )
        openTabs.append(detailTab)
        activateDetailTab(detailTab)
    }

    func openQueryTab(for connection: Connection) {
        var queryTab = QueryTab()
        queryTab.connectionID = connection.id
        queryTab.connectionName = connection.name
        queryTabs.append(queryTab)

        let detailTab = DetailTab(
            id: UUID(),
            title: "Query",
            icon: "terminal",
            kind: .queryEditor(queryTabID: queryTab.id)
        )
        openTabs.append(detailTab)
        activateDetailTab(detailTab)
    }

    func closeDetailTab(_ tabID: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = openTabs[idx]
        if case .queryEditor(let qid) = tab.kind {
            queryTabs.removeAll { $0.id == qid }
        }
        openTabs.remove(at: idx)
        if activeDetailTabID == tabID {
            if !openTabs.isEmpty {
                activateDetailTab(openTabs[min(idx, openTabs.count - 1)])
            } else {
                activeDetailTabID = nil
                selectedSidebarItem = nil
            }
        }
    }

    // MARK: - Tab activation

    /// Activates a detail tab and keeps `activeDetailTabID`, `selectedSidebarItem`,
    /// and `selectedConnectionID` in sync. Only updates `selectedConnectionID` when
    /// the tab has a definite connection (never clears it for connection-less file tabs).
    func activateDetailTab(_ tab: DetailTab) {
        activeDetailTabID = tab.id
        switch tab.kind {
        case .table(let cid, let s, let n):
            selectedSidebarItem = .table(connectionID: cid, schema: s, tableName: n)
            selectedConnectionID = cid
        case .queryEditor(let qid):
            selectedSidebarItem = nil
            if let connID = queryTabs.first(where: { $0.id == qid })?.connectionID {
                selectedConnectionID = connID
            }
        }
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
    var connectionID: UUID?
    var connectionName: String = ""
    var title: String = "Query"
    var sql: String = ""
    var sourceURL: URL? = nil
}

// MARK: - Detail tab model

struct DetailTab: Identifiable, Hashable {
    let id: UUID
    let title: String
    let icon: String
    let kind: Kind

    enum Kind: Hashable {
        case table(connectionID: UUID, schema: String, tableName: String)
        case queryEditor(queryTabID: UUID)
    }

    static func == (lhs: DetailTab, rhs: DetailTab) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
