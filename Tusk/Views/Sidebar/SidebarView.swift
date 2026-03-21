import SwiftUI

struct SidebarView: View {
    @Bindable var appState: AppState
    @AppStorage("tusk.sidebar.fontSize")    private var sidebarFontSize   = 13.0
    @AppStorage("tusk.sidebar.fontDesign") private var sidebarFontDesign: TuskFontDesign = .sansSerif

    var body: some View {
        VSplitView {
            // Top — connections + schema tree
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
                    ConnectionSection(connection: connection)
                }
            }
            .listStyle(.sidebar)
            .frame(minHeight: 120)
            .environment(\.font, .system(size: sidebarFontSize, design: sidebarFontDesign.design))

            // Bottom — file explorer
            FileExplorerView()
                .frame(minHeight: 120)
                .splitViewAutosaveName("tusk.sidebar.split")
                .environment(\.font, .system(size: sidebarFontSize, design: sidebarFontDesign.design))
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

    var isConnected: Bool { appState.isConnected(connection) }

    /// All schemas present in the cache, public first then alphabetical.
    var schemas: [(id: String, name: String, tables: [TableInfo], views: [TableInfo], enums: [EnumInfo], sequences: [SequenceInfo], functions: [FunctionInfo])] {
        let all       = appState.schemaTables[connection.id] ?? []
        let allEnums  = appState.schemaEnums[connection.id] ?? []
        let allSeqs   = appState.schemaSequences[connection.id] ?? []
        let allFuncs  = appState.schemaFunctions[connection.id] ?? []
        let allSchemas = Set(all.map { $0.schema })
            .union(allEnums.map { $0.schema })
            .union(allSeqs.map { $0.schema })
            .union(allFuncs.map { $0.schema })
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
        // Include connection.id in the row ID so that identically-named schemas
        // across different connections get distinct SwiftUI identities in the
        // flattened List — otherwise @State (isExpanded) is shared between them.
        return uniqueSchemas.map { (
            id:        "\(connection.id)-\($0)",
            name:      $0,
            tables:    tablesBySchema[$0] ?? [],
            views:     viewsBySchema[$0]  ?? [],
            enums:     enumsBySchema[$0]  ?? [],
            sequences: seqsBySchema[$0]   ?? [],
            functions: funcsBySchema[$0]  ?? []
        ) }
    }

    var body: some View {
        Section {
            if isConnected {
                ForEach(schemas, id: \.id) { schema in
                    SchemaRow(
                        schema: schema.name,
                        tables: schema.tables,
                        views: schema.views,
                        enums: schema.enums,
                        sequences: schema.sequences,
                        functions: schema.functions,
                        connection: connection
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

    @AppStorage("tusk.sidebar.fontSize")    private var sidebarFontSize   = 13.0
    @AppStorage("tusk.sidebar.fontDesign") private var sidebarFontDesign: TuskFontDesign = .sansSerif
    @State private var isExpanded: Bool
    @State private var tablesExpanded: Bool = true
    @State private var viewsExpanded: Bool = true
    @State private var enumsExpanded: Bool = true
    @State private var sequencesExpanded: Bool = true
    @State private var functionsExpanded: Bool = true

    init(schema: String, tables: [TableInfo], views: [TableInfo], enums: [EnumInfo], sequences: [SequenceInfo], functions: [FunctionInfo], connection: Connection) {
        self.schema = schema
        self.tables = tables
        self.views = views
        self.enums = enums
        self.sequences = sequences
        self.functions = functions
        self.connection = connection
        _isExpanded = State(initialValue: schema == "public")
    }

    var isEmpty: Bool { tables.isEmpty && views.isEmpty && enums.isEmpty && sequences.isEmpty && functions.isEmpty }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if !tables.isEmpty {
                DisclosureGroup(isExpanded: $tablesExpanded) {
                    ForEach(tables) { table in
                        Label {
                            Text(table.name)
                                .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        } icon: {
                            Image(systemName: "tablecells")
                        }
                        .tag(SidebarItem.table(
                            connectionID: connection.id,
                            schema: table.schema,
                            tableName: table.name
                        ))
                    }
                } label: {
                    Text("Tables")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { tablesExpanded.toggle() }
                }
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
            }
            if !enums.isEmpty {
                DisclosureGroup(isExpanded: $enumsExpanded) {
                    ForEach(enums) { enumInfo in
                        DisclosureGroup {
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
                    }
                } label: {
                    Text("Enums")
                        .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { enumsExpanded.toggle() }
                }
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
        }
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

            if let errorMsg = appState.schemaRefreshErrors[connection.id] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: sidebarFontSize - 3))
                    .foregroundStyle(.orange)
                    .help("Schema refresh failed: \(errorMsg)")
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .help(isConnected ? "Click to select" : isConnecting ? "Connecting…" : "Click to connect")
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
                Button("Disconnect") { appState.disconnect(connection) }
                Divider()
                Button("Refresh Schema") {
                    Task { try? await appState.refreshSchema(for: connection) }
                }
            } else if !isConnecting {
                Button("Connect") {
                    Task {
                        do { try await appState.connect(connection) }
                        catch { connectionError = error.localizedDescription }
                    }
                }
            }
            Divider()
            Button("Edit…") { appState.editingConnection = connection }
            Button("Delete", role: .destructive) { appState.removeConnection(connection) }
        }
    }
}
