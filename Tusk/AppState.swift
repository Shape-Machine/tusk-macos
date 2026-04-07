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

    // MARK: - Schema cache  (connectionID → tables / enums / sequences / functions)
    var schemaTables:       [UUID: [TableInfo]]     = [:]
    var schemaEnums:        [UUID: [EnumInfo]]      = [:]
    var schemaSequences:    [UUID: [SequenceInfo]]  = [:]
    var schemaFunctions:    [UUID: [FunctionInfo]]  = [:]
    var schemaRefreshErrors:[UUID: String]          = [:]
    /// keyed by connectionID → "schema.table" → TableSizeInfo
    var schemaTableSizes:   [UUID: [String: TableSizeInfo]] = [:]
    /// keyed by connectionID → sorted list of database names on that server
    var schemaDatabases:    [UUID: [String]]        = [:]
    /// keyed by connectionID → currently connected database (may differ from connection.database after a switch)
    var activeDatabase:     [UUID: String]          = [:]
    /// connectionIDs where the authenticated user has the PostgreSQL superuser role
    var superuserConnections: Set<UUID>             = []
    /// keyed by connectionID → cached role list (users + roles)
    var connectionRoles:      [UUID: [RoleInfo]]    = [:]

    // MARK: - UI state
    var isAddingConnection = false
    var isShowingSettings = false
    var editingConnection: Connection? = nil
    var connectingIDs: Set<UUID> = []
    var createTableTarget: CreateTableTarget? = nil

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

    func duplicateConnection(_ connection: Connection) {
        var copy = connection
        copy.id = UUID()
        copy.name = connection.name + " (copy)"
        // Copy credentials from Keychain
        if let password = KeychainManager.shared.password(for: connection.id) {
            KeychainManager.shared.setPassword(password, for: copy.id)
        }
        if let passphrase = KeychainManager.shared.sshPassphrase(for: connection.id) {
            KeychainManager.shared.setSshPassphrase(passphrase, for: copy.id)
        }
        connections.append(copy)
        ConnectionStore.shared.save(connections)
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
        // Prevent overlapping connect attempts for the same connection.
        // A second call while one is already in flight is silently dropped.
        guard !connectingIDs.contains(connection.id) else { return }
        connectingIDs.insert(connection.id)
        defer { connectingIDs.remove(connection.id) }

        // Clear the database list so a stale cache is never shown if the load below fails.
        schemaDatabases.removeValue(forKey: connection.id)

        // Build and connect the new client *before* tearing down the old one so
        // that table tabs backed by the existing client stay renderable during reconnect.
        var effectiveConnection = connection
        var newTunnel: SSHTunnel? = nil

        // Start SSH tunnel if enabled; the tunnel exposes a local port that
        // PostgresNIO will connect to instead of the real host/port.
        if connection.sshEnabled {
            let passphrase = KeychainManager.shared.sshPassphrase(for: connection.id)
            let tunnel = SSHTunnel()
            try await tunnel.start(connection: connection, passphrase: passphrase)
            newTunnel = tunnel
            let localPort = await tunnel.localPort
            effectiveConnection.host = "127.0.0.1"
            effectiveConnection.port = localPort
        }

        let password = KeychainManager.shared.password(for: connection.id) ?? ""
        let newClient = DatabaseClient()
        do {
            try await newClient.connect(to: effectiveConnection, password: password)
        } catch {
            await newClient.disconnect()
            if let tunnel = newTunnel { await tunnel.stop() }
            throw error
        }

        // New client is ready — atomically swap out the old one.
        if let oldClient = clients.removeValue(forKey: connection.id) {
            await oldClient.disconnect()
        }
        if let oldTunnel = tunnels.removeValue(forKey: connection.id) {
            await oldTunnel.stop()
        }
        if let tunnel = newTunnel { tunnels[connection.id] = tunnel }
        clients[connection.id] = newClient
        activeDatabase[connection.id] = connection.database
        selectedConnectionID = connection.id

        // Bind any file-based query tabs that were opened without a connection.
        for idx in queryTabs.indices where queryTabs[idx].sourceURL != nil && queryTabs[idx].connectionID == nil {
            queryTabs[idx].connectionID = connection.id
            queryTabs[idx].connectionName = connection.name
        }

        // refreshSchema calls loadSuperuserStatus on its success path;
        // call it here only as a fallback for when schema refresh fails.
        if (try? await refreshSchema(for: connection)) == nil {
            await loadSuperuserStatus(for: connection)
        }
        if UserDefaults.standard.bool(forKey: "tusk.sidebar.showTableSizes") {
            await loadTableSizes(for: connection)
        }
        await loadDatabases(for: connection)
    }

    func disconnect(_ connection: Connection) {
        let client = clients.removeValue(forKey: connection.id)
        let tunnel = tunnels.removeValue(forKey: connection.id)
        Task {
            await client?.disconnect()
            await tunnel?.stop()
        }
        schemaTables.removeValue(forKey: connection.id)
        schemaEnums.removeValue(forKey: connection.id)
        schemaSequences.removeValue(forKey: connection.id)
        schemaFunctions.removeValue(forKey: connection.id)
        schemaRefreshErrors.removeValue(forKey: connection.id)
        schemaTableSizes.removeValue(forKey: connection.id)
        schemaDatabases.removeValue(forKey: connection.id)
        activeDatabase.removeValue(forKey: connection.id)
        superuserConnections.remove(connection.id)
        connectionRoles.removeValue(forKey: connection.id)
        if createTableTarget?.connectionID == connection.id {
            createTableTarget = nil
        }

        // Close all detail tabs belonging to this connection
        let tabsToClose = openTabs.filter { tab in
            switch tab.kind {
            case .table(let cid, _, _): return cid == connection.id
            case .activityMonitor(let cid): return cid == connection.id
            case .roles(let cid): return cid == connection.id
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
        do {
            async let tables    = try client.tables()
            async let enums     = try client.enums()
            async let sequences = try client.sequences()
            async let functions = try client.functions()
            // Collect all results before writing — all-or-nothing to avoid partial cache state
            let t = try await tables
            let e = try await enums
            let s = try await sequences
            let f = try await functions
            schemaTables[connection.id]    = t
            schemaEnums[connection.id]     = e
            schemaSequences[connection.id] = s
            schemaFunctions[connection.id] = f
            schemaRefreshErrors.removeValue(forKey: connection.id)
            await loadSuperuserStatus(for: connection)
        } catch {
            schemaRefreshErrors[connection.id] = error.localizedDescription
            throw error
        }
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

    func openFileInEditor(url: URL) async {
        let connID = selectedConnectionID
        let connName = connID.flatMap { id in connections.first(where: { $0.id == id }) }?.name ?? ""

        // If this file is already open, update its connection to reflect the
        // current selection (handles gaining or losing a connection) and activate.
        if let existingIdx = queryTabs.firstIndex(where: { $0.sourceURL == url }),
           let detailTab = openTabs.first(where: {
               if case .queryEditor(let qid) = $0.kind { return qid == queryTabs[existingIdx].id }
               return false
           }) {
            queryTabs[existingIdx].connectionID = connID
            queryTabs[existingIdx].connectionName = connName
            activateDetailTab(detailTab)
            return
        }

        let sql = await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }.value
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

    func openActivityMonitor(for connection: Connection) {
        // If one is already open, just activate it.
        if let existing = openTabs.first(where: {
            if case .activityMonitor(let cid) = $0.kind { return cid == connection.id }
            return false
        }) {
            activateDetailTab(existing)
            return
        }
        let tab = DetailTab(
            id: UUID(),
            title: "Activity",
            icon: "waveform.path.ecg",
            kind: .activityMonitor(connectionID: connection.id)
        )
        openTabs.append(tab)
        activateDetailTab(tab)
    }

    func loadRoles(for connection: Connection) async {
        guard let client = clients[connection.id] else { return }
        let result = try? await client.query("""
            SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb,
                   rolcanlogin, rolreplication, rolconnlimit
            FROM pg_roles
            ORDER BY rolcanlogin DESC, rolname
            """)
        connectionRoles[connection.id] = result?.rows.compactMap { row -> RoleInfo? in
            guard let name = row[safe: 0]?.displayValue else { return nil }
            func bool(_ i: Int) -> Bool { row[safe: i]?.displayValue == "true" }
            let connLimit = Int(row[safe: 7]?.displayValue ?? "") ?? -1
            return RoleInfo(
                name: name,
                superuser: bool(1),
                inherit: bool(2),
                createRole: bool(3),
                createDB: bool(4),
                canLogin: bool(5),
                replication: bool(6),
                connLimit: connLimit
            )
        } ?? []
    }

    func openRolesBrowser(for connection: Connection) {
        if let existing = openTabs.first(where: {
            if case .roles(let cid) = $0.kind { return cid == connection.id }
            return false
        }) {
            activateDetailTab(existing)
            return
        }
        let tab = DetailTab(
            id: UUID(),
            title: "Users & Roles",
            icon: "person.2",
            kind: .roles(connectionID: connection.id)
        )
        openTabs.append(tab)
        activateDetailTab(tab)
    }

    func loadTableSizes(for connection: Connection) async {
        guard let client = clients[connection.id] else { return }
        guard let sizes = try? await client.tableSizes() else { return }
        var dict: [String: TableSizeInfo] = [:]
        for s in sizes { dict["\(s.schema).\(s.name)"] = s }
        schemaTableSizes[connection.id] = dict
    }

    func loadDatabases(for connection: Connection) async {
        guard let client = clients[connection.id] else { return }
        guard let dbs = try? await client.databases() else { return }
        schemaDatabases[connection.id] = dbs
    }

    func loadSuperuserStatus(for connection: Connection) async {
        guard let client = clients[connection.id] else { return }
        do {
            let result = try await client.query("SELECT rolsuper FROM pg_roles WHERE rolname = current_user")
            if case .bool(true) = result.rows.first?.first {
                superuserConnections.insert(connection.id)
            } else {
                superuserConnections.remove(connection.id)
            }
        } catch {
            // Leave existing badge state unchanged — a query failure is not evidence of non-superuser.
        }
    }

    func switchDatabase(connectionID: UUID, to database: String) async throws {
        guard let connection = connections.first(where: { $0.id == connectionID }) else { return }
        guard !connectingIDs.contains(connectionID) else { return }
        connectingIDs.insert(connectionID)
        defer { connectingIDs.remove(connectionID) }

        var effectiveConnection = connection
        effectiveConnection.database = database

        // Reuse the existing SSH tunnel if present
        if let tunnel = tunnels[connectionID] {
            let localPort = await tunnel.localPort
            effectiveConnection.host = "127.0.0.1"
            effectiveConnection.port = localPort
        }

        let password = KeychainManager.shared.password(for: connectionID) ?? ""
        let newClient = DatabaseClient()
        do {
            try await newClient.connect(to: effectiveConnection, password: password)
        } catch {
            await newClient.disconnect()
            throw error
        }

        if let oldClient = clients.removeValue(forKey: connectionID) {
            await oldClient.disconnect()
        }
        clients[connectionID] = newClient
        activeDatabase[connectionID] = database

        // Close table tabs belonging to this connection — they were for the old database
        let tabsToClose = openTabs.filter {
            if case .table(let cid, _, _) = $0.kind { return cid == connectionID }
            return false
        }
        for tab in tabsToClose { closeDetailTab(tab.id) }

        // Clear schema caches so stale data from the previous database is never shown
        // if the refresh below fails.
        schemaTables.removeValue(forKey: connectionID)
        schemaEnums.removeValue(forKey: connectionID)
        schemaSequences.removeValue(forKey: connectionID)
        schemaFunctions.removeValue(forKey: connectionID)
        schemaTableSizes.removeValue(forKey: connectionID)
        schemaRefreshErrors.removeValue(forKey: connectionID)

        if (try? await refreshSchema(for: connection)) == nil {
            await loadSuperuserStatus(for: connection)
        }
        if UserDefaults.standard.bool(forKey: "tusk.sidebar.showTableSizes") {
            await loadTableSizes(for: connection)
        }
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

    func setQueryTabConnection(tabID: UUID, connectionID: UUID, name: String) {
        guard let idx = queryTabs.firstIndex(where: { $0.id == tabID }) else { return }
        queryTabs[idx].connectionID = connectionID
        queryTabs[idx].connectionName = name
        // Keep selectedConnectionID in sync so global Database commands (⌘T,
        // Refresh Schema, Disconnect) target the connection shown in the active tab.
        let isActiveTab = openTabs.first(where: {
            if case .queryEditor(let qid) = $0.kind { return qid == tabID }
            return false
        })?.id == activeDetailTabID
        if isActiveTab { selectedConnectionID = connectionID }
    }

    func renameFileTab(from oldURL: URL, to newURL: URL) {
        guard let idx = queryTabs.firstIndex(where: { $0.sourceURL == oldURL }) else { return }
        queryTabs[idx].sourceURL = newURL
        queryTabs[idx].title = newURL.deletingPathExtension().lastPathComponent
    }

    func renameFolderTabs(from oldFolder: URL, to newFolder: URL) {
        let oldPrefix = oldFolder.standardized.path + "/"
        let newPrefix = newFolder.standardized.path + "/"
        for idx in queryTabs.indices {
            guard let sourceURL = queryTabs[idx].sourceURL else { continue }
            let sourcePath = sourceURL.standardized.path
            guard sourcePath.hasPrefix(oldPrefix) else { continue }
            let relativePath = String(sourcePath.dropFirst(oldPrefix.count))
            let updatedURL = URL(fileURLWithPath: newPrefix + relativePath)
            queryTabs[idx].sourceURL = updatedURL
            queryTabs[idx].title = updatedURL.deletingPathExtension().lastPathComponent
        }
    }

    func closeTabForFile(url: URL) {
        guard let qidx = queryTabs.firstIndex(where: { $0.sourceURL == url }) else { return }
        let qid = queryTabs[qidx].id
        guard let tab = openTabs.first(where: { if case .queryEditor(let id) = $0.kind { return id == qid }; return false })
        else { return }
        closeDetailTab(tab.id)
    }

    // MARK: - Tab activation

    /// Activates a detail tab and keeps `activeDetailTabID`, `selectedSidebarItem`,
    /// and `selectedConnectionID` in sync. Only updates `selectedConnectionID` when
    /// the tab has a definite connection (never clears it for connection-less file tabs).
    func activateNextTab() {
        guard openTabs.count > 1,
              let idx = openTabs.firstIndex(where: { $0.id == activeDetailTabID })
        else { return }
        activateDetailTab(openTabs[(idx + 1) % openTabs.count])
    }

    func activatePreviousTab() {
        guard openTabs.count > 1,
              let idx = openTabs.firstIndex(where: { $0.id == activeDetailTabID })
        else { return }
        activateDetailTab(openTabs[(idx + openTabs.count - 1) % openTabs.count])
    }

    func activateDetailTab(_ tab: DetailTab) {
        activeDetailTabID = tab.id
        switch tab.kind {
        case .table(let cid, let s, let n):
            selectedSidebarItem = .table(connectionID: cid, schema: s, tableName: n)
            selectedConnectionID = cid
        case .activityMonitor(let cid):
            selectedSidebarItem = nil
            selectedConnectionID = cid
        case .roles(let cid):
            selectedSidebarItem = nil
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
    var executions: [ExecutionEntry] = []
}

// MARK: - Detail tab model

struct DetailTab: Identifiable, Hashable {
    let id: UUID
    let title: String
    let icon: String
    let kind: Kind

    enum Kind: Hashable {
        case table(connectionID: UUID, schema: String, tableName: String)
        case activityMonitor(connectionID: UUID)
        case roles(connectionID: UUID)
        case queryEditor(queryTabID: UUID)
    }

    static func == (lhs: DetailTab, rhs: DetailTab) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Role model

struct RoleInfo: Identifiable {
    var id: String { name }
    let name: String
    let superuser: Bool
    let inherit: Bool
    let createRole: Bool
    let createDB: Bool
    let canLogin: Bool
    let replication: Bool
    let connLimit: Int  // -1 = no limit
}

// MARK: - Safe collection subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
