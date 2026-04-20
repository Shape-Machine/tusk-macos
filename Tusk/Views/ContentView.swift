import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(appState: appState)
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $appState.isAddingConnection) {
            AddConnectionSheet(connection: nil)
                .environment(\.font, .system(size: contentFontSize, design: contentFontDesign.design))
        }
        .sheet(item: $appState.editingConnection) { connection in
            AddConnectionSheet(connection: connection)
                .environment(\.font, .system(size: contentFontSize, design: contentFontDesign.design))
        }
    }
}

// MARK: - Detail area

struct DetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    var body: some View {
        VStack(spacing: 0) {
            if appState.openTabs.count > 1 {
                DetailTabBar()
                Divider()
            }
            activeContent
        }
        .environment(\.font, .system(size: contentFontSize, design: contentFontDesign.design))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appState.activeDetailTabID) {
            // Resign AppKit first responder (e.g. NSTextView in SQLTextEditor) when
            // switching tabs so hidden editors don't continue receiving keyboard input.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        if appState.openTabs.isEmpty {
            WelcomeView()
        } else {
            ZStack {
                ForEach(appState.openTabs) { tab in
                    tabContent(for: tab)
                        .opacity(tab.id == appState.activeDetailTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == appState.activeDetailTabID)
                        .accessibilityHidden(tab.id != appState.activeDetailTabID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: DetailTab) -> some View {
        switch tab.kind {
        case .table(let connID, let schema, let tableName):
            if let client = appState.clients[connID] {
                let isView = appState.schemaTables[connID]?
                    .first(where: { $0.schema == schema && $0.name == tableName })?.type == .view
                let isReadOnly = appState.connections.first(where: { $0.id == connID })?.isReadOnly ?? false
                TableDetailView(client: client, connectionID: connID, schemaName: schema, tableName: tableName, isView: isView, isReadOnly: isReadOnly)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .activityMonitor(let connID):
            if let client = appState.clients[connID],
               let connection = appState.connections.first(where: { $0.id == connID }) {
                ActivityMonitorView(client: client, connection: connection)
            }
        case .role(let connID, let roleName):
            if let client = appState.clients[connID],
               let connection = appState.connections.first(where: { $0.id == connID }) {
                RoleDetailView(connectionID: connID, roleName: roleName, client: client, connection: connection)
            }
        case .queryEditor(let queryTabID):
            if let queryTab = appState.queryTabs.first(where: { $0.id == queryTabID }) {
                let client = queryTab.connectionID.flatMap { appState.clients[$0] }
                QueryEditorView(tab: queryTab, client: client)
            }
        case .enumType(let connID, let schema, let enumName):
            if let client = appState.clients[connID],
               let connection = appState.connections.first(where: { $0.id == connID }) {
                EnumDetailView(schema: schema, enumName: enumName, client: client, connection: connection)
            }
        case .sequence(let connID, let schema, let sequenceName):
            if let client = appState.clients[connID],
               let connection = appState.connections.first(where: { $0.id == connID }) {
                SequenceDetailView(schema: schema, sequenceName: sequenceName, client: client, connection: connection)
            }
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

    /// Single scan of queryTabs — reused by resolvedTitle, tooltip, and connectionColor.
    private var queryTab: QueryTab? {
        guard case .queryEditor(let qid) = tab.kind else { return nil }
        return appState.queryTabs.first(where: { $0.id == qid })
    }

    /// Single scan of connections — reused by connectionColor for both tab kinds.
    private func connection(for connID: UUID) -> Connection? {
        appState.connections.first(where: { $0.id == connID })
    }

    var resolvedTitle: String { queryTab?.title ?? tab.title }

    var tooltip: String { queryTab?.sourceURL?.path ?? "" }

    var connectionColor: Color? {
        switch tab.kind {
        case .table(let connID, _, _):
            return connection(for: connID)?.color.color
        case .activityMonitor(let connID):
            return connection(for: connID)?.color.color
        case .role(let connID, _):
            return connection(for: connID)?.color.color
        case .queryEditor:
            guard let connID = queryTab?.connectionID else { return nil }
            return connection(for: connID)?.color.color
        case .enumType(let connID, _, _):
            return connection(for: connID)?.color.color
        case .sequence(let connID, _, _):
            return connection(for: connID)?.color.color
        }
    }

    var body: some View {
        // Use a Button for tab activation so it doesn't compete with the
        // close button the way .onTapGesture does on macOS.
        Button {
            appState.activateDetailTab(tab)
        } label: {
            HStack(spacing: 5) {
                if let color = connectionColor {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Image(systemName: tab.icon)
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(resolvedTitle)
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
