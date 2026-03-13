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
            if appState.openTabs.count > 1 {
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
        // Use a Button for tab activation so it doesn't compete with the
        // close button the way .onTapGesture does on macOS.
        Button {
            appState.activateDetailTab(tab)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(tab.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)
                // Reserve space so the title doesn't shift when close button overlaps
                Color.clear.frame(width: 22)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isActive ? Color(nsColor: .windowBackgroundColor) : .clear)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
        // Close button overlaid at full tab height — always wins hit-testing
        .overlay(alignment: .trailing) {
            Button {
                appState.closeDetailTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 34)
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
    }
}
