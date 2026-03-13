import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .sheet(isPresented: $appState.isAddingConnection) {
            AddConnectionSheet(connection: nil)
        }
        .sheet(item: $appState.editingConnection) { connection in
            AddConnectionSheet(connection: connection)
        }
    }
}

// MARK: - Detail area

struct DetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSidebarItem {
        case .table(let connID, let schema, let tableName):
            if let client = appState.clients[connID] {
                TableDetailView(client: client, connectionID: connID, schemaName: schema, tableName: tableName)
            }
        case .queryEditor(let tabID):
            if let tab = appState.queryTabs.first(where: { $0.id == tabID }),
               let client = appState.clients[tab.connectionID] {
                QueryEditorView(tab: tab, client: client)
                    .id(tab.id)
            }
        case .schema:
            SchemaView()
        case nil:
            WelcomeView()
        }
    }
}
