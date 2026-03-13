import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedSidebarItem },
            set: { appState.selectedSidebarItem = $0 }
        )) {
            ForEach(appState.connections) { connection in
                ConnectionSection(connection: connection)
            }
        }
        .listStyle(.sidebar)
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

    @State private var tablesExpanded = true

    var isConnected: Bool { appState.isConnected(connection) }
    var tablesToShow: [TableInfo] {
        (appState.schemaTables[connection.id] ?? []).filter { $0.type == .table }
    }

    var body: some View {
        Section {
            if isConnected {
                // Tables — full-row click toggles expand
                if !tablesToShow.isEmpty {
                    DisclosureGroup(isExpanded: $tablesExpanded) {
                        ForEach(tablesToShow) { table in
                            Label(table.name, systemImage: "tablecells")
                                .tag(SidebarItem.table(connectionID: connection.id, schema: table.schema, tableName: table.name))
                        }
                    } label: {
                        Text("Tables")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { tablesExpanded.toggle() }
                    }
                }
            }
        } header: {
            ConnectionHeader(connection: connection)
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

            Menu {
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
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
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
    }
}
