import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.sidebar.fontSize") private var sidebarFontSize = 13.0
    @State private var showingSettings = false

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
            .environment(\.font, .system(size: sidebarFontSize))

            // Bottom — file explorer
            FileExplorerView()
                .frame(minHeight: 120)
                .splitViewAutosaveName("tusk.sidebar.split")
                .environment(\.font, .system(size: sidebarFontSize))
        }
        .navigationTitle("Tusk")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Appearance settings")
                .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
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
    /// Each entry pairs a schema name with its BASE TABLE items only.
    var schemas: [(id: String, name: String, tables: [TableInfo])] {
        let all = appState.schemaTables[connection.id] ?? []
        let uniqueSchemas = Array(Set(all.map { $0.schema })).sorted {
            if $0 == "public" { return true }
            if $1 == "public" { return false }
            return $0 < $1
        }
        let tablesBySchema = Dictionary(grouping: all.filter { $0.type == .table }, by: { $0.schema })
        // Include connection.id in the row ID so that identically-named schemas
        // across different connections get distinct SwiftUI identities in the
        // flattened List — otherwise @State (isExpanded) is shared between them.
        return uniqueSchemas.map { (id: "\(connection.id)-\($0)", name: $0, tables: tablesBySchema[$0] ?? []) }
    }

    var body: some View {
        Section {
            if isConnected {
                ForEach(schemas, id: \.id) { schema in
                    SchemaRow(schema: schema.name, tables: schema.tables, connection: connection)
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
    let connection: Connection

    @AppStorage("tusk.sidebar.fontSize") private var sidebarFontSize = 13.0
    @State private var isExpanded: Bool

    init(schema: String, tables: [TableInfo], connection: Connection) {
        self.schema = schema
        self.tables = tables
        self.connection = connection
        _isExpanded = State(initialValue: schema == "public")
    }

    var isEmpty: Bool { tables.isEmpty }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(tables) { table in
                Label(table.name, systemImage: "tablecells")
                    .font(.system(size: sidebarFontSize))
                    .tag(SidebarItem.table(
                        connectionID: connection.id,
                        schema: table.schema,
                        tableName: table.name
                    ))
            }
        } label: {
            HStack(spacing: 6) {
                Text(schema)
                    .font(.system(size: sidebarFontSize))
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
    @AppStorage("tusk.sidebar.fontSize") private var sidebarFontSize = 13.0
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
                .font(.system(size: sidebarFontSize, weight: .semibold))
                .lineLimit(1)

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
