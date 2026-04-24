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

    // MARK: - Cloud SQL proxies (one per Cloud SQL connection)
    var cloudProxies: [UUID: CloudSQLProxy] = [:]
    var proxyStatuses: [UUID: CloudSQLProxy.Status] = [:]

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
    /// All non-system schema names for a connection, regardless of whether they contain objects.
    var schemaNamesCache:   [UUID: [String]]        = [:]
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
    /// Column info cache — keyed by connectionID → "schema.table" → [ColumnInfo] (#214)
    /// Invalidated on schema refresh and disconnect.
    var columnCache:          [UUID: [String: [ColumnInfo]]] = [:]

    // MARK: - UI state
    var isAddingConnection = false
    var isImportingPgpass = false
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
        guard !connectingIDs.contains(connection.id) else {
            throw NSError(domain: "Tusk", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Already connecting to \(connection.name). Please wait."])
        }
        connectingIDs.insert(connection.id)
        defer { connectingIDs.remove(connection.id) }

        // Clear the database list so a stale cache is never shown if the load below fails.
        schemaDatabases.removeValue(forKey: connection.id)

        // Build and connect the new client *before* tearing down the old one so
        // that table tabs backed by the existing client stay renderable during reconnect.
        var effectiveConnection = connection
        var newTunnel: SSHTunnel? = nil
        var newProxy: CloudSQLProxy? = nil

        if connection.connectionType == .cloudSQL {
            // Cloud SQL: start the Auth Proxy and patch host/port to the local end.
            proxyStatuses[connection.id] = .starting
            let proxy = CloudSQLProxy()
            do {
                let localPort = try await proxy.start(
                    instanceConnectionName: connection.cloudSQLInstanceConnectionName,
                    useIAMAuth: connection.useADC
                )
                newProxy = proxy
                proxyStatuses[connection.id] = .running
                effectiveConnection.host               = "127.0.0.1"
                effectiveConnection.port               = localPort
                effectiveConnection.useSSL             = false
                effectiveConnection.verifySSLCertificate = false
                // Monitor the proxy for unexpected termination and sync status into
                // proxyStatuses so the sidebar badge and Restart Proxy menu stay accurate.
                let connectionID = connection.id
                Task { [weak self] in
                    await self?.monitorProxy(proxy, connectionID: connectionID)
                }
            } catch {
                proxyStatuses[connection.id] = .crashed(error.localizedDescription)
                throw error
            }
        } else if connection.sshEnabled {
            // Start SSH tunnel if enabled; the tunnel exposes a local port that
            // PostgresNIO will connect to instead of the real host/port.
            let passphrase = connection.sshUseAgent ? nil : KeychainManager.shared.sshPassphrase(for: connection.id)
            let tunnel = SSHTunnel()
            try await tunnel.start(connection: connection, passphrase: passphrase)
            newTunnel = tunnel
            let localPort = await tunnel.localPort
            effectiveConnection.host = "127.0.0.1"
            effectiveConnection.port = localPort
        }

        let password: String
        if connection.connectionType == .cloudSQL && connection.useADC {
            password = try await Task.detached { try CloudSQLProxy.fetchADCToken() }.value
        } else {
            password = KeychainManager.shared.password(for: connection.id) ?? ""
        }

        let newClient = DatabaseClient()
        do {
            try await newClient.connect(to: effectiveConnection, password: password)
        } catch {
            await newClient.disconnect()
            if let tunnel = newTunnel { await tunnel.stop() }
            if let proxy = newProxy {
                proxyStatuses[connection.id] = .crashed(error.localizedDescription)
                await proxy.stop()
            }
            throw error
        }

        // New client is ready — atomically swap out the old one.
        if let oldClient = clients.removeValue(forKey: connection.id) {
            await oldClient.disconnect()
        }
        if let oldTunnel = tunnels.removeValue(forKey: connection.id) {
            await oldTunnel.stop()
        }
        if let oldProxy = cloudProxies.removeValue(forKey: connection.id) {
            await oldProxy.stop()
        }
        if let tunnel = newTunnel { tunnels[connection.id] = tunnel }
        if let proxy = newProxy { cloudProxies[connection.id] = proxy }
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
        // Load table sizes and databases concurrently — they are independent (#213)
        if UserDefaults.standard.bool(forKey: "tusk.sidebar.showTableSizes") {
            async let sizes: Void = loadTableSizes(for: connection)
            async let dbs:   Void = loadDatabases(for: connection)
            _ = await (sizes, dbs)
        } else {
            await loadDatabases(for: connection)
        }
    }

    func disconnect(_ connection: Connection) {
        let client = clients.removeValue(forKey: connection.id)
        let tunnel = tunnels.removeValue(forKey: connection.id)
        let proxy  = cloudProxies.removeValue(forKey: connection.id)
        proxyStatuses.removeValue(forKey: connection.id)
        Task {
            await client?.disconnect()
            await tunnel?.stop()
            await proxy?.stop()
        }
        schemaTables.removeValue(forKey: connection.id)
        schemaEnums.removeValue(forKey: connection.id)
        schemaSequences.removeValue(forKey: connection.id)
        schemaFunctions.removeValue(forKey: connection.id)
        schemaNamesCache.removeValue(forKey: connection.id)
        schemaRefreshErrors.removeValue(forKey: connection.id)
        schemaTableSizes.removeValue(forKey: connection.id)
        schemaDatabases.removeValue(forKey: connection.id)
        activeDatabase.removeValue(forKey: connection.id)
        superuserConnections.remove(connection.id)
        connectionRoles.removeValue(forKey: connection.id)
        columnCache.removeValue(forKey: connection.id)
        if createTableTarget?.connectionID == connection.id {
            createTableTarget = nil
        }

        // Close all detail tabs belonging to this connection
        let tabsToClose = openTabs.filter { tab in
            switch tab.kind {
            case .table(let cid, _, _): return cid == connection.id
            case .activityMonitor(let cid): return cid == connection.id
            case .role(let cid, _): return cid == connection.id
            case .queryEditor(let qid):
                return queryTabs.first(where: { $0.id == qid })?.connectionID == connection.id
            case .enumType(let cid, _, _): return cid == connection.id
            case .sequence(let cid, _, _): return cid == connection.id
            case .function(let cid, _, _, _): return cid == connection.id
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

    func restartProxy(for connection: Connection) async throws {
        guard connection.connectionType == .cloudSQL else { return }
        // Full reconnect rebuilds both the proxy and the Postgres client.
        try await connect(connection)
    }

    /// Awaits proxy termination, then syncs the crash status into proxyStatuses
    /// so the sidebar badge and "Restart Proxy" menu reflect reality.
    private func monitorProxy(_ proxy: CloudSQLProxy, connectionID: UUID) async {
        await proxy.waitForTermination()
        // Only update if we still own this proxy (user may have reconnected).
        guard cloudProxies[connectionID] === proxy else { return }
        if case .crashed(let msg) = await proxy.status {
            proxyStatuses[connectionID] = .crashed(msg)
        }
    }

    // MARK: - Schema refresh

    func refreshSchema(for connection: Connection) async throws {
        guard let client = clients[connection.id] else { return }
        do {
            async let tables    = try client.tables()
            async let enums     = try client.enums()
            async let sequences = try client.sequences()
            async let functions = try client.functions()
            async let names     = try client.schemaNames()
            // Collect all results before writing — all-or-nothing to avoid partial cache state
            let t = try await tables
            let e = try await enums
            let s = try await sequences
            let f = try await functions
            let n = try await names
            schemaTables[connection.id]    = t
            schemaEnums[connection.id]     = e
            schemaSequences[connection.id] = s
            schemaFunctions[connection.id] = f
            schemaNamesCache[connection.id] = n
            schemaRefreshErrors.removeValue(forKey: connection.id)
            // Column metadata may have changed — invalidate the cache (#214)
            columnCache.removeValue(forKey: connection.id)
            await loadSuperuserStatus(for: connection)
        } catch {
            schemaRefreshErrors[connection.id] = error.localizedDescription
            throw error
        }
    }

    /// Returns cached column info for a table, or fetches and caches it if not yet available.
    /// Cache is invalidated on schema refresh and disconnect (#214).
    func cachedColumns(connectionID: UUID, schema: String, table: String, using client: DatabaseClient) async throws -> [ColumnInfo] {
        let key = "\(schema).\(table)"
        if let cached = columnCache[connectionID]?[key] {
            return cached
        }
        let cols = try await client.columns(schema: schema, table: table)
        if columnCache[connectionID] == nil { columnCache[connectionID] = [:] }
        columnCache[connectionID]?[key] = cols
        return cols
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
        guard let result = try? await client.query("""
            SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb,
                   rolcanlogin, rolreplication, rolconnlimit,
                   to_char(rolvaliduntil, 'YYYY-MM-DD') AS validuntil
            FROM pg_roles
            ORDER BY rolcanlogin DESC, rolname
            """) else { return }  // leave connectionRoles nil so callers can retry
        connectionRoles[connection.id] = result.rows.compactMap { row -> RoleInfo? in
            guard let name = row[safe: 0]?.displayValue, name != "NULL" else { return nil }
            func bool(_ i: Int) -> Bool { row[safe: i]?.displayValue == "true" }
            let connLimit = Int(row[safe: 7]?.displayValue ?? "") ?? -1
            let validUntil: String? = {
                guard case .text(let s) = row[safe: 8] else { return nil }
                return s
            }()
            return RoleInfo(
                name: name,
                superuser: bool(1),
                inherit: bool(2),
                createRole: bool(3),
                createDB: bool(4),
                canLogin: bool(5),
                replication: bool(6),
                connLimit: connLimit,
                validUntil: validUntil
            )
        }
    }

    func openRoleTab(for connection: Connection, roleName: String) {
        if let existing = openTabs.first(where: {
            if case .role(let cid, let n) = $0.kind { return cid == connection.id && n == roleName }
            return false
        }) {
            activateDetailTab(existing)
            return
        }
        let tab = DetailTab(
            id: UUID(),
            title: roleName,
            icon: "person",
            kind: .role(connectionID: connection.id, roleName: roleName)
        )
        openTabs.append(tab)
        activateDetailTab(tab)
    }

    func openEnumTab(for connection: Connection, schema: String, enumName: String) {
        if let existing = openTabs.first(where: {
            if case .enumType(let cid, let s, let n) = $0.kind { return cid == connection.id && s == schema && n == enumName }
            return false
        }) {
            activateDetailTab(existing)
            return
        }
        let tab = DetailTab(
            id: UUID(),
            title: enumName,
            icon: "list.bullet",
            kind: .enumType(connectionID: connection.id, schema: schema, enumName: enumName)
        )
        openTabs.append(tab)
        activateDetailTab(tab)
    }

    func openSequenceTab(for connection: Connection, schema: String, sequenceName: String) {
        if let existing = openTabs.first(where: {
            if case .sequence(let cid, let s, let n) = $0.kind { return cid == connection.id && s == schema && n == sequenceName }
            return false
        }) {
            activateDetailTab(existing)
            return
        }
        let tab = DetailTab(
            id: UUID(),
            title: sequenceName,
            icon: "arrow.clockwise",
            kind: .sequence(connectionID: connection.id, schema: schema, sequenceName: sequenceName)
        )
        openTabs.append(tab)
        activateDetailTab(tab)
    }

    func openFunctionTab(for connection: Connection, fn: FunctionInfo) {
        if let existing = openTabs.first(where: {
            if case .function(let cid, _, _, let o) = $0.kind { return cid == connection.id && o == fn.oid }
            return false
        }) {
            activateDetailTab(existing)
            return
        }
        let tab = DetailTab(
            id: UUID(),
            title: fn.name,
            icon: "function",
            kind: .function(connectionID: connection.id, schema: fn.schema, functionName: fn.name, oid: fn.oid)
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

        // Reuse the existing SSH tunnel or Cloud SQL proxy if present
        if let tunnel = tunnels[connectionID] {
            let localPort = await tunnel.localPort
            effectiveConnection.host = "127.0.0.1"
            effectiveConnection.port = localPort
        } else if let proxy = cloudProxies[connectionID] {
            // If the proxy has crashed, restart it before switching databases.
            if case .crashed = await proxy.status {
                await proxy.stop()  // clean up pipe handlers / FDs before replacing
                let newProxy = CloudSQLProxy()
                proxyStatuses[connectionID] = .starting
                let localPort = try await newProxy.start(
                    instanceConnectionName: connection.cloudSQLInstanceConnectionName,
                    useIAMAuth: connection.useADC
                )
                cloudProxies[connectionID] = newProxy
                proxyStatuses[connectionID] = .running
                Task { [weak self] in await self?.monitorProxy(newProxy, connectionID: connectionID) }
                effectiveConnection.host = "127.0.0.1"
                effectiveConnection.port = localPort
            } else {
                let localPort = await proxy.localPort
                effectiveConnection.host = "127.0.0.1"
                effectiveConnection.port = localPort
            }
            effectiveConnection.useSSL             = false
            effectiveConnection.verifySSLCertificate = false
        }

        let password: String
        if connection.connectionType == .cloudSQL && connection.useADC {
            password = try await Task.detached { try CloudSQLProxy.fetchADCToken() }.value
        } else {
            password = KeychainManager.shared.password(for: connectionID) ?? ""
        }
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
        schemaNamesCache.removeValue(forKey: connectionID)
        schemaTableSizes.removeValue(forKey: connectionID)
        schemaRefreshErrors.removeValue(forKey: connectionID)
        columnCache.removeValue(forKey: connectionID)

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
        case .role(let cid, _):
            selectedSidebarItem = nil
            selectedConnectionID = cid
        case .queryEditor(let qid):
            selectedSidebarItem = nil
            if let connID = queryTabs.first(where: { $0.id == qid })?.connectionID {
                selectedConnectionID = connID
            }
        case .enumType(let cid, _, _):
            selectedSidebarItem = nil
            selectedConnectionID = cid
        case .sequence(let cid, _, _):
            selectedSidebarItem = nil
            selectedConnectionID = cid
        case .function(let cid, _, _, _):
            selectedSidebarItem = nil
            selectedConnectionID = cid
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
        case role(connectionID: UUID, roleName: String)
        case queryEditor(queryTabID: UUID)
        case enumType(connectionID: UUID, schema: String, enumName: String)
        case sequence(connectionID: UUID, schema: String, sequenceName: String)
        case function(connectionID: UUID, schema: String, functionName: String, oid: UInt32)
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
    let connLimit: Int      // -1 = no limit
    let validUntil: String? // nil = infinity / no expiry
}

// MARK: - Safe collection subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
