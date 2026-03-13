import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
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
        VStack(spacing: 0) {
            if !appState.openTabs.isEmpty {
                DetailTabBar()
                Divider()
            }
            activeContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var activeContent: some View {
        if let tabID = appState.activeDetailTabID,
           let tab = appState.openTabs.first(where: { $0.id == tabID }) {
            switch tab.kind {
            case .table(let connID, let schema, let tableName):
                if let client = appState.clients[connID] {
                    TableDetailView(client: client, connectionID: connID, schemaName: schema, tableName: tableName)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Connecting…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .queryEditor(let queryTabID):
                if let queryTab = appState.queryTabs.first(where: { $0.id == queryTabID }) {
                    let client = queryTab.connectionID.flatMap { appState.clients[$0] }
                    QueryEditorView(tab: queryTab, client: client)
                        .id(queryTab.id)
                }
            }
        } else {
            WelcomeView()
        }
    }
}

// MARK: - Tab bar

private struct DetailTabBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(appState.openTabs) { tab in
                    DetailTabItem(tab: tab)
                    Divider().frame(height: 34)
                }
            }
        }
        .frame(height: 34)
        .background(.bar)
    }
}

private struct DetailTabItem: View {
    @Environment(AppState.self) private var appState
    let tab: DetailTab

    var isActive: Bool { appState.activeDetailTabID == tab.id }

    var tooltip: String {
        guard case .queryEditor(let qid) = tab.kind,
              let path = appState.queryTabs.first(where: { $0.id == qid })?.sourceURL?.path
        else { return "" }
        return path
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab.icon)
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .secondary)
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            Button {
                appState.closeDetailTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Close tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0)
        .frame(height: 34)
        .background(isActive ? Color(nsColor: .windowBackgroundColor) : .clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .help(tooltip)
        .onTapGesture {
            appState.activateDetailTab(tab)
        }
    }
}
