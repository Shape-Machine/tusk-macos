import SwiftUI

struct SidebarView: View {
    @Bindable var appState: AppState
    @AppStorage("tusk.sidebar.fontSize")       private var sidebarFontSize    = 13.0
    @AppStorage("tusk.sidebar.fontDesign")     private var sidebarFontDesign: TuskFontDesign = .sansSerif
    @AppStorage("tusk.sidebar.showTableSizes") private var showTableSizes     = false
    @State private var filterText: String = ""

    var body: some View {
        VSplitView {
            // Top — connections + schema tree
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: sidebarFontSize - 1))
                    TextField("Filter…", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
                List(selection: Binding(
                    get: { appState.selectedSidebarItem },
                    set: { newItem in
                        appState.selectedSidebarItem = newItem
                        if let item = newItem,
                           case .table(let cid, let schema, let name) = item {
                            appState.openOrActivateTableTab(
                                connectionID: cid,
                                schema: schema,
                                tableName: name
                            )
                        }
                    }
                )) {
                    ForEach(appState.connections) { connection in
                        ConnectionSection(connection: connection, filterText: filterText)
                    }
                }
                .listStyle(.sidebar)
                .environment(\.font, .system(size: sidebarFontSize, design: sidebarFontDesign.design))
            }
            .frame(minHeight: 120)
            .onChange(of: appState.clients.count) { _, _ in
                filterText = ""
            }
            .onChange(of: appState.selectedConnectionID) { _, _ in
                filterText = ""
            }

            // Bottom — file explorer
            FileExplorerView()
                .frame(minHeight: 120)
                .splitViewAutosaveName("tusk.sidebar.split")
                .environment(\.font, .system(size: sidebarFontSize, design: sidebarFontDesign.design))
        }
        .onChange(of: showTableSizes) { _, enabled in
            guard enabled else { return }
            for connection in appState.connections where appState.isConnected(connection) {
                Task { await appState.loadTableSizes(for: connection) }
            }
        }
        .sheet(item: $appState.createTableTarget) { target in
            if let client = appState.clients[target.connectionID],
               let connection = appState.connections.first(where: { $0.id == target.connectionID }) {
                CreateTableSheet(schemaName: target.schema, client: client) {
                    try? await appState.refreshSchema(for: connection)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Connection unavailable")
                        .font(.headline)
                    Button("Dismiss") { appState.createTableTarget = nil }
                }
                .frame(width: 280, height: 100)
            }
        }
        .navigationTitle("Tusk")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.isShowingSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Appearance settings")
                .popover(isPresented: $appState.isShowingSettings, arrowEdge: .bottom) {
                    SettingsPopover()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isAddingConnection = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add connection")
            }
        }
    }
}

// MARK: - Per-connection section

private struct ConnectionSection: View {
    @Environment(AppState.self) private var appState
    let connection: Connection
    var filterText: String = ""

    var isConnected: Bool { appState.isConnected(connection) }

    /// All schemas present in the cache, public first then alphabetical.
    /// When `filterText` is non-empty, each schema's object arrays are narrowed to
    /// names containing the filter string (case-insensitive), and schemas with no
    /// matching objects are omitted entirely.
    var schemas: [(id: String, name: String, tables: [TableInfo], views: [TableInfo], enums: [EnumInfo], sequences: [SequenceInfo], functions: [FunctionInfo])] {
        let all       = appState.schemaTables[connection.id] ?? []
        let allEnums  = appState.schemaEnums[connection.id] ?? []
        let allSeqs   = appState.schemaSequences[connection.id] ?? []
        let allFuncs  = appState.schemaFunctions[connection.id] ?? []
        let allSchemas = Set(all.map { $0.schema })
            .union(allEnums.map { $0.schema })
            .union(allSeqs.map { $0.schema })
            .union(allFuncs.map { $0.schema })
            .union(appState.schemaNamesCache[connection.id] ?? [])
        let uniqueSchemas = allSchemas.sorted {
            if $0 == "public" { return true }
            if $1 == "public" { return false }
            return $0 < $1
        }
        let tablesBySchema = Dictionary(grouping: all.filter { $0.type == .table }, by: { $0.schema })
        let viewsBySchema  = Dictionary(grouping: all.filter { $0.type == .view },  by: { $0.schema })
        let enumsBySchema  = Dictionary(grouping: allEnums, by: { $0.schema })
        let seqsBySchema   = Dictionary(grouping: allSeqs,  by: { $0.schema })
        let funcsBySchema  = Dictionary(grouping: allFuncs, by: { $0.schema })

        let filter = filterText.lowercased()

        func matches(_ name: String) -> Bool {
            filter.isEmpty || name.lowercased().contains(filter)
        }

        // Include connection.id in the row ID so that identically-named schemas
        // across different connections get distinct SwiftUI identities in the
        // flattened List — otherwise @State (isExpanded) is shared between them.
        let rows = uniqueSchemas.map { schema -> (id: String, name: String, tables: [TableInfo], views: [TableInfo], enums: [EnumInfo], sequences: [SequenceInfo], functions: [FunctionInfo]) in
            (
                id:        "\(connection.id)-\(schema)",
                name:      schema,
                tables:    (tablesBySchema[schema] ?? []).filter { matches($0.name) },
                views:     (viewsBySchema[schema]  ?? []).filter { matches($0.name) },
                enums:     (enumsBySchema[schema]  ?? []).filter { matches($0.name) },
                sequences: (seqsBySchema[schema]   ?? []).filter { matches($0.name) },
                functions: (funcsBySchema[schema]  ?? []).filter { matches($0.signature) }
            )
        }

        if filter.isEmpty { return rows }
        return rows.filter {
            $0.name.lowercased().contains(filter) ||
            !$0.tables.isEmpty || !$0.views.isEmpty ||
            !$0.enums.isEmpty  || !$0.sequences.isEmpty || !$0.functions.isEmpty
        }
    }

    var body: some View {
        Section {
            if isConnected {
                UsersAndRolesSection(connection: connection)
                ForEach(schemas, id: \.id) { schema in
                    SchemaRow(
                        schema: schema.name,
                        tables: schema.tables,
                        views: schema.views,
                        enums: schema.enums,
                        sequences: schema.sequences,
                        functions: schema.functions,
                        connection: connection,
                        tableSizes: appState.schemaTableSizes[connection.id] ?? [:]
                    )
                }
            }
        } header: {
            ConnectionHeader(connection: connection)
        }
    }
}

// MARK: - Schema row (public auto-expanded)

private struct SchemaRow: View {
    let schema: String
    let tables: [TableInfo]
    let views: [TableInfo]
    let enums: [EnumInfo]
    let sequences: [SequenceInfo]
    let functions: [FunctionInfo]
    let connection: Connection
    var tableSizes: [String: TableSizeInfo] = [:]

    @Environment(AppState.self) private var appState
    @AppStorage("tusk.sidebar.fontSize")      private var sidebarFontSize    = 13.0
    @AppStorage("tusk.sidebar.fontDesign")    private var sidebarFontDesign: TuskFontDesign = .sansSerif
    @AppStorage("tusk.sidebar.showTableSizes") private var showTableSizes    = false
    @State private var isExpanded: Bool
    @State private var tablesExpanded: Bool = false
    @State private var viewsExpanded: Bool = false
    @State private var enumsExpanded: Bool = false
    @State private var sequencesExpanded: Bool = false
    @State private var functionsExpanded: Bool = false

    init(schema: String, tables: [TableInfo], views: [TableInfo], enums: [EnumInfo], sequences: [SequenceInfo], functions: [FunctionInfo], connection: Connection, tableSizes: [String: TableSizeInfo] = [:]) {
        self.schema = schema
        self.tables = tables
        self.views = views
        self.enums = enums
        self.sequences = sequences
        self.functions = functions
        self.connection = connection
        self.tableSizes = tableSizes
        _isExpanded = State(initialValue: schema == "public")
    }

    var isEmpty: Bool { tables.isEmpty && views.isEmpty && enums.isEmpty && sequences.isEmpty && functions.isEmpty }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if !tables.isEmpty {
                DisclosureGroup(isExpanded: $tablesExpanded) {
                    ForEach(tables) { table in
                        Label {
                            HStack(spacing: 4) {
                                Text(table.name)
                                    .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                                if showTableSizes, let info = tableSizes["\(table.schema).\(table.name)"] {
                                    Text("\(info.totalSize) · \(info.rowEstimate.formatted()) rows · idx \(info.indexSize)")
                                        .font(.system(size: sidebarFontSize - 2, design: sidebarFontDesign.design))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } icon: {
                            Image(systemName: "tablecells")
                        }
                        .tag(SidebarItem.table(
                            connectionID: connection.id,
                            schema: table.schema,
                            tableName: table.name
                        ))
                        .contextMenu {
                            if appState.isConnected(connection) && !connection.isReadOnly {
                                Button("Rename…") { renameTable(table) }
                                Divider()
                                Button("Truncate Table…") { truncateTable(table) }
                                Button("Drop Table…")     { dropTable(table) }
                            }
                        }
                    }
                } label: {
                    Text("Tables")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { tablesExpanded.toggle() }
                        .contextMenu {
                            if appState.isConnected(connection) && !connection.isReadOnly {
                                Button("New Table…") {
                                    appState.createTableTarget = CreateTableTarget(
                                        schema: schema,
                                        connectionID: connection.id
                                    )
                                }
                            }
                        }
                }
                .animation(nil, value: tablesExpanded)
            }
            if !views.isEmpty {
                DisclosureGroup(isExpanded: $viewsExpanded) {
                    ForEach(views) { view in
                        Label {
                            Text(view.name)
                                .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        } icon: {
                            Image(systemName: "eye")
                        }
                        .tag(SidebarItem.table(
                            connectionID: connection.id,
                            schema: view.schema,
                            tableName: view.name
                        ))
                    }
                } label: {
                    Text("Views")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { viewsExpanded.toggle() }
                }
                .animation(nil, value: viewsExpanded)
            }
            if !enums.isEmpty {
                DisclosureGroup(isExpanded: $enumsExpanded) {
                    ForEach(enums) { enumInfo in
                        EnumValueRow(enumInfo: enumInfo)
                    }
                } label: {
                    Text("Enums")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { enumsExpanded.toggle() }
                }
                .animation(nil, value: enumsExpanded)
            }
            if !sequences.isEmpty {
                DisclosureGroup(isExpanded: $sequencesExpanded) {
                    ForEach(sequences) { seq in
                        Label {
                            Text(seq.name)
                                .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        } icon: {
                            Image(systemName: "number")
                        }
                    }
                } label: {
                    Text("Sequences")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { sequencesExpanded.toggle() }
                }
                .animation(nil, value: sequencesExpanded)
            }
            if !functions.isEmpty {
                DisclosureGroup(isExpanded: $functionsExpanded) {
                    ForEach(functions) { fn in
                        Label {
                            Text(fn.signature)
                                .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        } icon: {
                            Image(systemName: "function")
                        }
                    }
                } label: {
                    Text("Functions")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { functionsExpanded.toggle() }
                }
                .animation(nil, value: functionsExpanded)
            }
        } label: {
            HStack(spacing: 6) {
                Text(schema)
                    .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                    .foregroundStyle(isEmpty ? .tertiary : .primary)
                if isEmpty {
                    Text("empty")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quinary, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
            .contextMenu {
                if appState.isConnected(connection) && !connection.isReadOnly {
                    Button("New Table…") {
                        appState.createTableTarget = CreateTableTarget(
                            schema: schema,
                            connectionID: connection.id
                        )
                    }
                    Divider()
                    Button("Rename Schema…") { renameSchema() }
                    Button("Drop Schema…")   { dropSchema() }
                }
            }
        }
        .animation(nil, value: isExpanded)
    }

    // MARK: - Rename schema

    private func renameSchema() {
        guard let client = appState.clients[connection.id] else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Schema \"\(schema)\""
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = schema
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != schema else { return }

        Task {
            do {
                _ = try await client.query("ALTER SCHEMA \(quoteIdentifier(schema)) RENAME TO \(quoteIdentifier(newName));")
                // Close open tabs whose table was in the renamed schema — their schema name is now stale
                let tabsToClose = appState.openTabs.filter {
                    guard case .table(let cid, let s, _) = $0.kind else { return false }
                    return cid == connection.id && s == schema
                }
                for tab in tabsToClose { appState.closeDetailTab(tab.id) }
                try? await appState.refreshSchema(for: connection)
            } catch {
                let err = NSAlert()
                err.messageText = "Rename Schema Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    // MARK: - Drop schema

    private func dropSchema() {
        guard let client = appState.clients[connection.id] else { return }

        let alert = NSAlert()
        alert.messageText = "Drop Schema \"\(schema)\"?"
        alert.informativeText = "This permanently removes the schema. The schema must be empty — use \"Drop with CASCADE\" to also drop all objects inside it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Drop Schema")
        alert.addButton(withTitle: "Drop with CASCADE")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return }
        let cascade = response == .alertSecondButtonReturn

        Task {
            do {
                let sql = "DROP SCHEMA \(quoteIdentifier(schema))\(cascade ? " CASCADE" : "");"
                _ = try await client.query(sql)
                // Close any open tabs whose table lives in the dropped schema
                let tabsToClose = appState.openTabs.filter {
                    guard case .table(let cid, let s, _) = $0.kind else { return false }
                    return cid == connection.id && s == schema
                }
                for tab in tabsToClose { appState.closeDetailTab(tab.id) }
                try? await appState.refreshSchema(for: connection)
            } catch {
                let err = NSAlert()
                err.messageText = "Drop Schema Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    // MARK: - Rename table

    private func renameTable(_ table: TableInfo) {
        guard let client = appState.clients[connection.id] else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Table \"\(table.name)\""
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = table.name
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != table.name else { return }

        Task {
            do {
                let sql = "ALTER TABLE \(quoteIdentifier(table.schema)).\(quoteIdentifier(table.name)) RENAME TO \(quoteIdentifier(newName));"
                _ = try await client.query(sql)
                if let old = appState.openTabs.first(where: {
                    guard case .table(let cid, let s, let n) = $0.kind else { return false }
                    return cid == connection.id && s == table.schema && n == table.name
                }) {
                    appState.closeDetailTab(old.id)
                    appState.openOrActivateTableTab(connectionID: connection.id, schema: table.schema, tableName: newName)
                }
                try? await appState.refreshSchema(for: connection)
                if appState.schemaTableSizes[connection.id] != nil {
                    await appState.loadTableSizes(for: connection)
                }
            } catch {
                let err = NSAlert()
                err.messageText = "Rename Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }
    // MARK: - Truncate table

    private func truncateTable(_ table: TableInfo) {
        guard let client = appState.clients[connection.id] else { return }

        let alert = NSAlert()
        alert.messageText = "Truncate Table \"\(table.name)\"?"
        alert.informativeText = "This removes all rows from the table. The table structure is kept. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Truncate")
        alert.addButton(withTitle: "Cancel")

        let restartCheck = NSButton(checkboxWithTitle: "Restart sequences (RESTART IDENTITY)", target: nil, action: nil)
        restartCheck.frame = NSRect(x: 0, y: 0, width: 300, height: 18)
        restartCheck.state = .off
        alert.accessoryView = restartCheck

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let restartIdentity = restartCheck.state == .on
        let restartClause = restartIdentity ? " RESTART IDENTITY" : ""
        let sql = "TRUNCATE TABLE \(quoteIdentifier(table.schema)).\(quoteIdentifier(table.name))\(restartClause);"

        Task {
            do {
                _ = try await client.query(sql)
                try? await appState.refreshSchema(for: connection)
                if appState.schemaTableSizes[connection.id] != nil {
                    await appState.loadTableSizes(for: connection)
                }
            } catch {
                let err = NSAlert()
                err.messageText = "Truncate Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    // MARK: - Drop table

    private func dropTable(_ table: TableInfo) {
        guard let client = appState.clients[connection.id] else { return }

        Task {
            let refs: [IncomingReference]
            do {
                refs = try await client.incomingReferences(schema: table.schema, table: table.name)
            } catch {
                let err = NSAlert()
                err.messageText = "Could Not Check Dependencies"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
                return
            }

            let alert = NSAlert()
            alert.messageText = "Drop Table \"\(table.name)\"?"
            alert.alertStyle = .warning

            var hasDependents = false
            if refs.isEmpty {
                alert.informativeText = "This permanently removes the table and all its data. This action cannot be undone."
                alert.addButton(withTitle: "Drop Table")
                alert.addButton(withTitle: "Cancel")
            } else {
                hasDependents = true
                let tableList = Array(Set(refs.map { "\($0.fromSchema).\($0.fromTable)" })).sorted().joined(separator: ", ")
                alert.informativeText = "Table \"\(table.name)\" is referenced by foreign keys in: \(tableList).\n\n\"Drop Table\" will fail unless those constraints are removed first. \"Drop with CASCADE\" also drops all dependent objects — use with care."
                alert.addButton(withTitle: "Drop Table")
                alert.addButton(withTitle: "Drop with CASCADE")
                alert.addButton(withTitle: "Cancel")
            }

            let response = alert.runModal()

            let isCancelled = hasDependents ? response == .alertThirdButtonReturn
                                            : response == .alertSecondButtonReturn
            guard !isCancelled else { return }

            let cascade = hasDependents && response == .alertSecondButtonReturn
            let sql = "DROP TABLE IF EXISTS \(quoteIdentifier(table.schema)).\(quoteIdentifier(table.name))\(cascade ? " CASCADE" : "");"

            do {
                _ = try await client.query(sql)
                if let tab = appState.openTabs.first(where: {
                    guard case .table(let cid, let s, let n) = $0.kind else { return false }
                    return cid == connection.id && s == table.schema && n == table.name
                }) {
                    appState.closeDetailTab(tab.id)
                }
                try? await appState.refreshSchema(for: connection)
                if appState.schemaTableSizes[connection.id] != nil {
                    await appState.loadTableSizes(for: connection)
                }
            } catch {
                let err = NSAlert()
                err.messageText = "Drop Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }
}

// MARK: - Users & Roles sidebar section

private struct UsersAndRolesSection: View {
    @Environment(AppState.self) private var appState
    let connection: Connection

    @AppStorage("tusk.sidebar.fontSize")   private var sidebarFontSize   = 13.0
    @AppStorage("tusk.sidebar.fontDesign") private var sidebarFontDesign: TuskFontDesign = .sansSerif

    @State private var isExpanded = false
    @State private var usersExpanded = false
    @State private var rolesExpanded = false
    @State private var showingCreateRole = false

    private var roles: [RoleInfo] { appState.connectionRoles[connection.id] ?? [] }
    private var users: [RoleInfo] { roles.filter { $0.canLogin } }
    private var roleOnly: [RoleInfo] { roles.filter { !$0.canLogin } }
    private var isLoaded: Bool { appState.connectionRoles[connection.id] != nil }
    private var isSuperuser: Bool { appState.superuserConnections.contains(connection.id) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if !isLoaded {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…")
                        .font(.system(size: sidebarFontSize - 1, design: sidebarFontDesign.design))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
            } else {
                if !users.isEmpty {
                    DisclosureGroup(isExpanded: $usersExpanded) {
                        ForEach(users) { user in
                            Label {
                                Text(user.name)
                                    .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                            } icon: {
                                Image(systemName: "person")
                            }
                            .onTapGesture { appState.openRoleTab(for: connection, roleName: user.name) }
                        }
                    } label: {
                        Text("Users")
                            .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { usersExpanded.toggle() }
                    }
                    .animation(nil, value: usersExpanded)
                }

                if !roleOnly.isEmpty {
                    DisclosureGroup(isExpanded: $rolesExpanded) {
                        ForEach(roleOnly) { role in
                            Label {
                                Text(role.name)
                                    .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                            } icon: {
                                Image(systemName: "person.2")
                            }
                            .onTapGesture { appState.openRoleTab(for: connection, roleName: role.name) }
                        }
                    } label: {
                        Text("Roles")
                            .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { rolesExpanded.toggle() }
                    }
                    .animation(nil, value: rolesExpanded)
                }

                if users.isEmpty && roleOnly.isEmpty {
                    Text("No roles found")
                        .font(.system(size: sidebarFontSize - 1, design: sidebarFontDesign.design))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }
        } label: {
            HStack(spacing: 0) {
                Label {
                    Text("Users & Roles")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                } icon: {
                    Image(systemName: "person.2")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    isExpanded.toggle()
                    if isExpanded && !isLoaded {
                        Task { await appState.loadRoles(for: connection) }
                    }
                }

                if isSuperuser && !connection.isReadOnly && appState.clients[connection.id] != nil {
                    Button {
                        showingCreateRole = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: sidebarFontSize - 2))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Create new user or role")
                }
            }
        }
        .animation(nil, value: isExpanded)
        .sheet(isPresented: $showingCreateRole) {
            if let client = appState.clients[connection.id] {
                CreateRoleSheet(client: client, connection: connection) {
                    await appState.loadRoles(for: connection)
                }
            }
        }
    }
}

// MARK: - Per-enum value row (needs own @State to suppress animation)

private struct EnumValueRow: View {
    let enumInfo: EnumInfo
    @AppStorage("tusk.sidebar.fontSize")    private var sidebarFontSize   = 13.0
    @AppStorage("tusk.sidebar.fontDesign") private var sidebarFontDesign: TuskFontDesign = .sansSerif
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(enumInfo.values, id: \.self) { value in
                Text(value)
                    .font(.system(size: sidebarFontSize - 1, design: sidebarFontDesign.design))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        } label: {
            Label {
                Text(enumInfo.name)
                    .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
            } icon: {
                Image(systemName: "list.bullet")
            }
        }
        .animation(nil, value: isExpanded)
    }
}

// MARK: - Connection header row

private struct ConnectionHeader: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.sidebar.fontSize")    private var sidebarFontSize   = 13.0
    @AppStorage("tusk.sidebar.fontDesign") private var sidebarFontDesign: TuskFontDesign = .sansSerif
    let connection: Connection

    @State private var connectionError: String? = nil

    var isConnected: Bool { appState.isConnected(connection) }
    var isConnecting: Bool { appState.connectingIDs.contains(connection.id) }
    var isSelected: Bool { appState.selectedConnectionID == connection.id }
    var databases: [String] { appState.schemaDatabases[connection.id] ?? [] }
    var currentDatabase: String { appState.activeDatabase[connection.id] ?? connection.database }

    var body: some View {
        HStack(spacing: 6) {
            if isConnecting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 8, height: 8)
                    .tint(connection.color.color)
            } else if isConnected {
                Circle()
                    .fill(connection.color.color)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .strokeBorder(connection.color.color, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            }

            Text(connection.name)
                .font(.system(size: sidebarFontSize, weight: .semibold, design: sidebarFontDesign.design))
                .lineLimit(1)

            if appState.superuserConnections.contains(connection.id) {
                Image(systemName: "crown.fill")
                    .font(.system(size: sidebarFontSize - 3))
                    .foregroundStyle(.orange)
                    .help("Superuser")
            }

            if connection.isReadOnly {
                Image(systemName: "lock.fill")
                    .font(.system(size: sidebarFontSize - 3))
                    .foregroundStyle(.secondary)
                    .help("Read-only connection")
            }

            if connection.connectionType == .cloudSQL {
                CloudSQLProxyBadge(
                    status: appState.proxyStatuses[connection.id],
                    fontSize: sidebarFontSize
                )
            }

            if let errorMsg = appState.schemaRefreshErrors[connection.id] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: sidebarFontSize - 3))
                    .foregroundStyle(.orange)
                    .help("Schema refresh failed: \(errorMsg)")
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .help({
            let status = isConnected ? "Click to select" : isConnecting ? "Connecting…" : "Click to connect"
            let notes = connection.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return notes.isEmpty ? status : "\(notes)\n\(status)"
        }())
        .onTapGesture {
            if isConnected {
                appState.selectedConnectionID = connection.id
            } else if !isConnecting {
                Task {
                    do { try await appState.connect(connection) }
                    catch { connectionError = error.localizedDescription }
                }
            }
        }
        .alert("Connection Failed", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK") { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
        .contextMenu {
            if isConnected {
                Button("New Query") { appState.openQueryTab(for: connection) }
                Button("Activity Monitor") { appState.openActivityMonitor(for: connection) }
                Divider()
                Button("Disconnect") { appState.disconnect(connection) }
                Divider()
                Button("Refresh Schema") {
                    Task { try? await appState.refreshSchema(for: connection) }
                }
                if !connection.isReadOnly {
                    Divider()
                    Button("New Schema…") { createSchema(for: connection) }
                }
                if databases.count > 1 {
                    Divider()
                    Menu("Switch Database") {
                        ForEach(databases, id: \.self) { db in
                            Button {
                                Task {
                                    do {
                                        try await appState.switchDatabase(connectionID: connection.id, to: db)
                                    } catch {
                                        connectionError = error.localizedDescription
                                    }
                                }
                            } label: {
                                if db == currentDatabase {
                                    Label(db, systemImage: "checkmark")
                                } else {
                                    Text(db)
                                }
                            }
                            .disabled(db == currentDatabase)
                        }
                    }
                }
            } else if !isConnecting {
                Button("Connect") {
                    Task {
                        do { try await appState.connect(connection) }
                        catch { connectionError = error.localizedDescription }
                    }
                }
            }
            if connection.connectionType == .cloudSQL, isConnected {
                if case .crashed = appState.proxyStatuses[connection.id] {
                    Divider()
                    Button("Restart Proxy") {
                        Task { try? await appState.restartProxy(for: connection) }
                    }
                }
            }
            Divider()
            Button("Duplicate") { appState.duplicateConnection(connection) }
            Button("Edit…") { appState.editingConnection = connection }
            Button("Delete", role: .destructive) { appState.removeConnection(connection) }
        }
    }

    // MARK: - Create schema

    private func createSchema(for connection: Connection) {
        guard let client = appState.clients[connection.id] else { return }

        let alert = NSAlert()
        alert.messageText = "New Schema"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = "schema_name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            do {
                _ = try await client.query("CREATE SCHEMA \(quoteIdentifier(name));")
                try? await appState.refreshSchema(for: connection)
            } catch {
                let err = NSAlert()
                err.messageText = "Create Schema Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }
}

// MARK: - Cloud SQL proxy status badge

private struct CloudSQLProxyBadge: View {
    let status: CloudSQLProxy.Status?
    let fontSize: Double

    var body: some View {
        let (icon, tint, label): (String, Color, String) = {
            switch status {
            case .running:
                return ("cloud.fill", .green, "cloud-sql-proxy running")
            case .crashed(let msg):
                return ("cloud.slash.fill", .red, "cloud-sql-proxy crashed: \(msg)")
            default:
                return ("cloud", .secondary, "cloud-sql-proxy starting…")
            }
        }()
        Image(systemName: icon)
            .font(.system(size: fontSize - 3))
            .foregroundStyle(tint)
            .help(label)
    }
}
