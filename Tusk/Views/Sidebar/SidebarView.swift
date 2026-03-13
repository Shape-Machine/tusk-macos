import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

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

            // Bottom — file explorer
            FileExplorerView()
                .frame(minHeight: 120)
        }
        .navigationTitle("Tusk")
        .toolbar {
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
    var schemas: [(name: String, tables: [TableInfo])] {
        let all = appState.schemaTables[connection.id] ?? []
        let uniqueSchemas = Array(Set(all.map { $0.schema })).sorted {
            if $0 == "public" { return true }
            if $1 == "public" { return false }
            return $0 < $1
        }
        let tablesBySchema = Dictionary(grouping: all.filter { $0.type == .table }, by: { $0.schema })
        return uniqueSchemas.map { (name: $0, tables: tablesBySchema[$0] ?? []) }
    }

    var body: some View {
        Section {
            if isConnected {
                ForEach(schemas, id: \.name) { schema in
                    SchemaRow(schema: schema.name, tables: schema.tables, connection: connection)
                }
            }
        } header: {
            ConnectionHeader(connection: connection)
        }
    }
}

// MARK: - Schema row (collapsed by default)

private struct SchemaRow: View {
    let schema: String
    let tables: [TableInfo]
    let connection: Connection

    @State private var isExpanded = false

    var isEmpty: Bool { tables.isEmpty }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(tables) { table in
                Label(table.name, systemImage: "tablecells")
                    .tag(SidebarItem.table(
                        connectionID: connection.id,
                        schema: table.schema,
                        tableName: table.name
                    ))
            }
        } label: {
            HStack(spacing: 6) {
                Text(schema)
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
    let connection: Connection

    var isConnected: Bool { appState.isConnected(connection) }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : connection.color.color)
                .frame(width: 8, height: 8)

            Text(connection.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isConnected {
                Task {
                    do { try await appState.connect(connection) }
                    catch { print("Connection error: \(error)") }
                }
            }
        }
        .contextMenu {
            if isConnected {
                Button("New Query") { appState.openQueryTab(for: connection) }
                Button("Disconnect") { appState.disconnect(connection) }
                Divider()
                Button("Refresh Schema") {
                    Task { try? await appState.refreshSchema(for: connection) }
                }
            } else {
                Button("Connect") {
                    Task {
                        do { try await appState.connect(connection) }
                        catch { print("Connection error: \(error)") }
                    }
                }
            }
            Divider()
            Button("Edit…") { appState.editingConnection = connection }
            Button("Delete", role: .destructive) { appState.removeConnection(connection) }
        }
    }
}
