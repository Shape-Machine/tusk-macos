import SwiftUI

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0
    let tab: QueryTab
    let client: DatabaseClient?

    @State private var sql: String = ""
    @State private var selectedRange: NSRange = NSRange()
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
                    Task { await runCurrentQuery() }
                } label: {
                    Label("Run Current", systemImage: "play")
                        .font(.callout)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(client == nil || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                SQLTextEditor(text: $sql, selectedRange: $selectedRange, fontSize: contentFontSize)
                if sql.isEmpty {
                    Text("-- Write SQL here · ⌘↵ to run · ⌘⇧↵ for current")
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

    private func runCurrentQuery() async {
        let liveConnectionID = appState.queryTabs.first(where: { $0.id == tab.id })?.connectionID
        guard let client = liveConnectionID.flatMap({ appState.clients[$0] }) else { return }

        let candidate: String
        let nsSQL = sql as NSString
        if selectedRange.length > 0 {
            let safeLocation = min(selectedRange.location, nsSQL.length)
            let safeLength   = min(selectedRange.length, nsSQL.length - safeLocation)
            candidate = nsSQL.substring(with: NSRange(location: safeLocation, length: safeLength))
        } else {
            candidate = statementAtCursor(in: sql, cursorLocation: selectedRange.location) ?? sql
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Statement at cursor

    /// Returns the SQL statement that contains `cursorLocation` (UTF-16 offset),
    /// or nil if the position is empty. Handles single-quoted strings, dollar-quoted
    /// strings, line comments, and block comments; semicolons only terminate
    /// statements in the normal state.
    private func statementAtCursor(in sql: String, cursorLocation: Int) -> String? {
        let ns  = sql as NSString
        let len = ns.length
        guard len > 0, cursorLocation >= 0 else { return nil }
        let cursor = min(cursorLocation, len)

        let apostrophe = unichar(UnicodeScalar("'").value)
        let dollar     = unichar(UnicodeScalar("$").value)
        let semicolon  = unichar(UnicodeScalar(";").value)
        let hyphen     = unichar(UnicodeScalar("-").value)
        let slash      = unichar(UnicodeScalar("/").value)
        let asterisk   = unichar(UnicodeScalar("*").value)
        let newline    = unichar(UnicodeScalar("\n").value)
        let cr         = unichar(UnicodeScalar("\r").value)
        let underscore = unichar(UnicodeScalar("_").value)

        enum State { case normal, singleQuote, dollarQuote([unichar]), lineComment, blockComment }

        var state: State = .normal
        var stmtStart = 0
        var i = 0

        func stmtSubstring() -> String? {
            let s = ns.substring(with: NSRange(location: stmtStart, length: i - stmtStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        while i < len {
            let ch   = ns.character(at: i)
            let next = i + 1 < len ? ns.character(at: i + 1) : 0

            switch state {
            case .normal:
                if ch == apostrophe {
                    state = .singleQuote; i += 1
                } else if ch == hyphen && next == hyphen {
                    state = .lineComment; i += 2
                } else if ch == slash && next == asterisk {
                    state = .blockComment; i += 2
                } else if ch == dollar {
                    // Try to match $tag$ or $$
                    var j = i + 1
                    while j < len {
                        let jc = ns.character(at: j)
                        let isIdent = (jc >= 65 && jc <= 90) || (jc >= 97 && jc <= 122) ||
                                      (jc >= 48 && jc <= 57) || jc == underscore
                        guard isIdent else { break }
                        j += 1
                    }
                    if j < len && ns.character(at: j) == dollar {
                        var tag: [unichar] = []
                        for k in i...j { tag.append(ns.character(at: k)) }
                        state = .dollarQuote(tag); i = j + 1
                    } else {
                        i += 1
                    }
                } else if ch == semicolon {
                    if cursor >= stmtStart && cursor <= i { return stmtSubstring() }
                    stmtStart = i + 1; i += 1
                } else {
                    i += 1
                }

            case .singleQuote:
                if ch == apostrophe && next == apostrophe { i += 2 }
                else if ch == apostrophe { state = .normal; i += 1 }
                else { i += 1 }

            case .dollarQuote(let tag):
                let tl = tag.count
                if i + tl <= len && (0..<tl).allSatisfy({ ns.character(at: i + $0) == tag[$0] }) {
                    state = .normal; i += tl
                } else { i += 1 }

            case .lineComment:
                if ch == newline || ch == cr { state = .normal }
                i += 1

            case .blockComment:
                if ch == asterisk && next == slash { state = .normal; i += 2 }
                else { i += 1 }
            }
        }

        // Cursor is in the final statement (no trailing semicolon)
        return cursor >= stmtStart ? stmtSubstring() : nil
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
                                        cellText(cell)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                            .border(Color(nsColor: .separatorColor), width: 0.5)
                                            .onTapGesture(count: 2) {
                                                let dtype = colIndex < result.columns.count ? result.columns[colIndex].dataType : ""
                                                expandedCell = CellDetailContent(id: "\(rowIndex):\(colIndex)", value: cell.displayValue, columnDataType: dtype)
                                            }
                                            .contextMenu {
                                                Button("Copy Cell") {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(cell.displayValue, forType: .string)
                                                }
                                                Button("View Full Value") {
                                                    let dtype = colIndex < result.columns.count ? result.columns[colIndex].dataType : ""
                                                    expandedCell = CellDetailContent(id: "\(rowIndex):\(colIndex)", value: cell.displayValue, columnDataType: dtype)
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
            CellDetailView(value: content.value, columnDataType: content.columnDataType)
        }
        .onChange(of: result.id) {
            selectedRows.removeAll()
            lastSelectedRow = nil
            keyboardCursor = nil
        }
    }

    // MARK: - Cell rendering

    private func cellText(_ cell: QueryCell) -> Text {
        if cell.isNull {
            return Text("NULL").foregroundStyle(.tertiary).italic()
        }
        if case .text(let s) = cell, s.isEmpty {
            return Text("''").foregroundStyle(.tertiary).italic()
        }
        return Text(cell.displayValue).foregroundStyle(.primary)
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
                if lastSelectedRow == rowIndex { lastSelectedRow = nil }
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
    let columnDataType: String
}

struct CellDetailView: View {
    let value: String
    let columnDataType: String
    @Environment(\.dismiss) private var dismiss
    @State private var showTree = true

    private var parsedJSON: JSONValue? {
        guard columnDataType == "json" || columnDataType == "jsonb" else { return nil }
        return parseJSONValue(value)
    }

    private var prettyJSON: String {
        guard let data = value.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return value }
        return str
    }

    var body: some View {
        let json = parsedJSON   // parse exactly once per render
        VStack(spacing: 0) {
            HStack {
                Text("Cell Value")
                    .fontWeight(.semibold)
                Spacer()
                if json != nil {
                    Picker("", selection: $showTree) {
                        Text("Tree").tag(true)
                        Text("Raw").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
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

            if let j = json, showTree {
                JSONTreeView(value: j)
            } else {
                let displayText = json != nil ? prettyJSON : value
                ScrollView([.horizontal, .vertical]) {
                    if displayText.isEmpty {
                        Text("''")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    } else {
                        Text(displayText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(minWidth: 480, minHeight: 300)
    }
}

// MARK: - JSON tree view

private indirect enum JSONValue: Sendable {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

private func parseJSONValue(_ string: String) -> JSONValue? {
    guard let data = string.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    else { return nil }
    return convertAny(obj)
}

private func convertAny(_ any: Any) -> JSONValue {
    if any is NSNull { return .null }
    if let n = any as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
        return .bool(n.boolValue)
    }
    if let n = any as? NSNumber { return .number(n.stringValue) }
    if let s = any as? String { return .string(s) }
    if let obj = any as? [String: Any] {
        let pairs = obj.keys.sorted().map { k in (k, convertAny(obj[k]!)) }
        return .object(pairs)
    }
    if let arr = any as? [Any] {
        return .array(arr.map { convertAny($0) })
    }
    return .string(String(describing: any))
}

private struct JSONTreeView: View {
    let value: JSONValue

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            JSONNodeView(value: value, depth: 0)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct JSONNodeView: View {
    let value: JSONValue
    let depth: Int
    @State private var isExpanded: Bool

    init(value: JSONValue, depth: Int) {
        self.value = value
        self.depth = depth
        _isExpanded = State(initialValue: depth < 2)
    }

    var body: some View {
        Group {
            switch value {
            case .object(let pairs):
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                        HStack(alignment: .top, spacing: 4) {
                            Text(pair.0 + ":")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                            JSONNodeView(value: pair.1, depth: depth + 1)
                        }
                        .padding(.leading, 16)
                    }
                } label: {
                    Text(isExpanded ? "{" : "{ \(pairs.count) }")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

            case .array(let items):
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(idx):")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            JSONNodeView(value: item, depth: depth + 1)
                        }
                        .padding(.leading, 16)
                    }
                } label: {
                    Text(isExpanded ? "[" : "[ \(items.count) ]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

            case .string(let s):
                Text("\"\(s)\"")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

            case .number(let n):
                Text(n)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.teal)

            case .bool(let b):
                Text(b ? "true" : "false")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.blue)

            case .null:
                Text("null")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }
}
