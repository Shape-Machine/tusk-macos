import SwiftUI

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0
    let tab: QueryTab
    let client: DatabaseClient?

    @State private var sql: String = ""
    @State private var result: QueryResult? = nil
    @State private var resultIsCapped = false
    @State private var error: String? = nil
    @State private var isRunning = false
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var savedIndicatorTask: Task<Void, Never>? = nil
    @State private var savedIndicator = false

    var body: some View {
        VSplitView {
            // Editor pane
            editorPane
                .frame(minHeight: 120)
                .splitViewAutosaveName("tusk.queryeditor.split")

            // Results pane
            resultsPane
                .frame(minHeight: 100)
        }
        .onAppear {
            sql = tab.sql
            result = tab.result
            resultIsCapped = tab.resultIsCapped
            error = tab.error
        }
        .onChange(of: sql) { _, newValue in
            // Sync in-memory state
            if let index = appState.queryTabs.firstIndex(where: { $0.id == tab.id }) {
                appState.queryTabs[index].sql = newValue
            }
            // Debounced auto-save to disk (500 ms)
            guard tab.sourceURL != nil else { return }
            autoSaveTask?.cancel()
            autoSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let url = tab.sourceURL else { return }
                do {
                    try newValue.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    return
                }
                savedIndicatorTask?.cancel()
                savedIndicatorTask = Task {
                    savedIndicator = true
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { savedIndicator = false }
                }
            }
        }
    }

    // MARK: - Editor pane

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                connectionPicker
                Spacer()
                if savedIndicator {
                    Label("Saved", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                if isRunning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await runQuery() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.callout)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(client == nil || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            ZStack(alignment: .topLeading) {
                SQLTextEditor(text: $sql, fontSize: contentFontSize)
                if sql.isEmpty {
                    Text("-- Write SQL here · ⌘↵ to run")
                        .font(.system(size: contentFontSize, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Connection picker

    private var connectionPicker: some View {
        let active = appState.connections.filter { appState.clients[$0.id] != nil }
        return Group {
            if active.isEmpty {
                Label("No connection", systemImage: "bolt.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(active) { connection in
                        Button {
                            appState.setQueryTabConnection(
                                tabID: tab.id,
                                connectionID: connection.id,
                                name: connection.name
                            )
                            result = nil
                            error = nil
                            resultIsCapped = false
                            persistResultStateToTab()
                        } label: {
                            if tab.connectionID == connection.id {
                                Label(connection.name, systemImage: "checkmark")
                            } else {
                                Text(connection.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(client != nil ? tab.connectionName : "No connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Results pane

    private var resultsPane: some View {
        VStack(spacing: 0) {
            HStack {
                if let result {
                    Text("\(result.rows.count) row\(result.rows.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.3fs", result.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if resultIsCapped {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Showing first \(tuskPageSize) rows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Spacer()
                if let result, !result.rows.isEmpty {
                    Button {
                        copyRowsAsCSV(columns: result.columns, rows: result.rows)
                    } label: {
                        Label("Copy CSV", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Copy all rows as CSV")
                    Button {
                        copyRowsAsJSON(columns: result.columns, rows: result.rows)
                    } label: {
                        Label("Copy JSON", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Copy all rows as JSON")
                    Button {
                        exportCSV(result)
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if let result {
                ResultsGrid(result: result)
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
    }

    // MARK: - Run query

    private func runQuery() async {
        // Read the live connectionID from appState rather than the prop, which
        // may be a stale copy if the connection picker was just changed.
        let liveConnectionID = appState.queryTabs.first(where: { $0.id == tab.id })?.connectionID
        guard let client = liveConnectionID.flatMap({ appState.clients[$0] }) else { return }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isRunning = true
        error = nil
        result = nil
        resultIsCapped = false
        persistResultStateToTab()

        let (finalSQL, capped) = cappedSQL(trimmed)
        do {
            let r = try await client.query(finalSQL, rowLimit: tuskPageSize)
            result = r
            resultIsCapped = capped && r.rows.count == tuskPageSize
        } catch {
            self.error = error.localizedDescription
        }

        isRunning = false
        persistResultStateToTab()
    }

    private func persistResultStateToTab() {
        guard let index = appState.queryTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        appState.queryTabs[index].result = result
        appState.queryTabs[index].resultIsCapped = resultIsCapped
        appState.queryTabs[index].error = error
    }

    /// Wraps SELECT/WITH queries in a subquery capped at `tuskPageSize`.
    /// Non-SELECT statements are returned unchanged.
    /// Note: the subquery wrapping is a DB-side optimisation; the hard row cap
    /// is enforced independently by DatabaseClient.query(rowLimit:).
    private func cappedSQL(_ sql: String) -> (sql: String, capped: Bool) {
        // Strip trailing single-line comments before stripping semicolons —
        // otherwise "SELECT ... ; -- comment" leaves the semicolon in place
        // and the capped subquery becomes invalid SQL.
        let stripped = sql
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s*--[^\r\n]*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ";").union(.whitespacesAndNewlines))
        let lower = stripped.lowercased()
        guard lower.hasPrefix("select") || lower.hasPrefix("with") else {
            return (sql, false)
        }
        return ("SELECT * FROM (\(stripped)) AS _tusk_result LIMIT \(tuskPageSize)", true)
    }

    // MARK: - Export

    private func exportCSV(_ result: QueryResult) {
        exportResultAsCSV(result, defaultName: "query_result")
    }
}

// MARK: - Results grid

struct ResultsGrid: View {
    let result: QueryResult
    var copyAsInsert: (([[QueryCell]]) -> Void)? = nil

    @State private var expandedCell: CellDetailContent? = nil
    @State private var selectedRows: Set<Int> = []
    @State private var lastSelectedRow: Int? = nil
    @FocusState private var isFocused: Bool
    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var keyboardCursor: Int? = nil

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            // Data rows — only rows near the viewport are materialised
                            ForEach(result.rows.indices, id: \.self) { rowIndex in
                                let row = result.rows[rowIndex]
                                let isSelected = selectedRows.contains(rowIndex)
                                HStack(spacing: 0) {
                                    ForEach(row.indices, id: \.self) { colIndex in
                                        let cell = row[colIndex]
                                        Text(cell.displayValue)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .foregroundStyle(cell.isNull ? .tertiary : .primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                            .border(Color(nsColor: .separatorColor), width: 0.5)
                                            .onTapGesture(count: 2) {
                                                expandedCell = CellDetailContent(id: "\(rowIndex):\(colIndex)", value: cell.displayValue)
                                            }
                                            .contextMenu {
                                                Button("Copy Cell") {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(cell.displayValue, forType: .string)
                                                }
                                                Button("View Full Value") {
                                                    expandedCell = CellDetailContent(id: "\(rowIndex):\(colIndex)", value: cell.displayValue)
                                                }
                                            }
                                    }
                                }
                                .id(rowIndex)
                                .background(rowBackground(rowIndex: rowIndex, isSelected: isSelected))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isFocused = true
                                    handleRowTap(rowIndex: rowIndex)
                                }
                                .contextMenu {
                                    let selectionRows = selectedRows.isEmpty ? [row] : selectedRows.sorted().compactMap { result.rows.indices.contains($0) ? result.rows[$0] : nil }
                                    let count = selectedRows.isEmpty ? 1 : selectedRows.count
                                    let label = count == 1 ? "Row" : "\(count) Rows"
                                    Button("Copy \(label) as CSV") {
                                        copyRowsAsCSV(columns: result.columns, rows: selectionRows)
                                    }
                                    Button("Copy \(label) as JSON") {
                                        copyRowsAsJSON(columns: result.columns, rows: selectionRows)
                                    }
                                    if let copyAsInsert {
                                        Button("Copy \(label) as INSERT") {
                                            copyAsInsert(selectionRows)
                                        }
                                    }
                                }
                            }
                        } header: {
                            // Header row — pinned to top while scrolling vertically
                            HStack(spacing: 0) {
                                ForEach(result.columns) { col in
                                    Text(col.name)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .border(Color(nsColor: .separatorColor), width: 0.5)
                                }
                            }
                        }
                    }
                    .frame(
                        minWidth: geo.size.width,
                        minHeight: geo.size.height,
                        alignment: .topLeading
                    )
                    .onAppear { scrollProxy = proxy }
                }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown]) { press in
                handleKeyNavigation(press: press, viewHeight: geo.size.height)
                return .handled
            }
            .onKeyPress(keys: [.init("a")], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                handleSelectAll()
                return .handled
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $expandedCell) { content in
            CellDetailView(value: content.value)
        }
        .onChange(of: result.id) {
            selectedRows.removeAll()
            lastSelectedRow = nil
            keyboardCursor = nil
        }
    }

    // MARK: - Row background

    private func rowBackground(rowIndex: Int, isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        return rowIndex.isMultiple(of: 2)
            ? Color(nsColor: .controlAlternatingRowBackgroundColors[0])
            : Color(nsColor: .controlAlternatingRowBackgroundColors[1])
    }

    // MARK: - Mouse selection

    private func handleRowTap(rowIndex: Int) {
        keyboardCursor = rowIndex
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedRows.contains(rowIndex) {
                selectedRows.remove(rowIndex)
            } else {
                selectedRows.insert(rowIndex)
                lastSelectedRow = rowIndex
            }
        } else if flags.contains(.shift), let anchor = lastSelectedRow {
            let range = anchor <= rowIndex ? anchor...rowIndex : rowIndex...anchor
            selectedRows = Set(range)
        } else {
            selectedRows = [rowIndex]
            lastSelectedRow = rowIndex
        }
    }

    // MARK: - Keyboard navigation

    private func handleKeyNavigation(press: KeyPress, viewHeight: CGFloat) {
        guard !result.rows.isEmpty else { return }
        let lastRow = result.rows.count - 1
        let rowHeight = contentFontSize + 6
        let pageRows = max(1, Int(viewHeight / rowHeight))
        let currentCursor = keyboardCursor ?? lastSelectedRow ?? 0
        let shift = press.modifiers.contains(.shift)

        let delta: Int
        switch press.key {
        case .upArrow:   delta = -1
        case .downArrow: delta = 1
        case .pageUp:    delta = -pageRows
        case .pageDown:  delta = pageRows
        default: return
        }

        let newCursor = max(0, min(lastRow, currentCursor + delta))
        keyboardCursor = newCursor

        if shift, let anchor = lastSelectedRow {
            selectedRows = Set(min(anchor, newCursor)...max(anchor, newCursor))
        } else {
            selectedRows = [newCursor]
            lastSelectedRow = newCursor
        }

        scrollProxy?.scrollTo(newCursor, anchor: .center)
    }

    private func handleSelectAll() {
        guard !result.rows.isEmpty else { return }
        selectedRows = Set(result.rows.indices)
        lastSelectedRow = 0
        keyboardCursor = 0
        scrollProxy?.scrollTo(0, anchor: .top)
    }
}

// MARK: - Cell detail sheet

private struct CellDetailContent: Identifiable {
    let id: String   // "\(rowIndex):\(colIndex)" — stable across re-renders
    let value: String
}

struct CellDetailView: View {
    let value: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cell Value")
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 480, minHeight: 300)
    }
}
