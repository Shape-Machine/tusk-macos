import SwiftUI

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0
    let tab: QueryTab
    let client: DatabaseClient?

    @State private var sql: String = ""
    @State private var selectedRange: NSRange = NSRange()
    @State private var executions: [ExecutionEntry] = []
    @State private var selectedResultTab: Int = 0   // 0 = Log, 1+ = Result N
    @State private var isRunning = false
    @State private var executeTask: Task<Void, Never>? = nil
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var savedIndicatorTask: Task<Void, Never>? = nil
    @State private var savedIndicator = false
    @State private var copiedCSV = false
    @State private var copiedCSVTask: Task<Void, Never>? = nil
    @State private var copiedJSON = false
    @State private var copiedJSONTask: Task<Void, Never>? = nil

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
            executions = tab.executions
        }
        .onDisappear {
            if isRunning { cancelExecution() }
        }
        .onChange(of: sql) { _, newValue in
            // Sync in-memory state
            if let index = appState.queryTabs.firstIndex(where: { $0.id == tab.id }) {
                appState.queryTabs[index].sql = newValue
            }
            // Debounced auto-save to disk (500 ms) — file write runs off @MainActor
            guard let saveURL = tab.sourceURL else { return }
            autoSaveTask?.cancel()
            autoSaveTask = Task.detached(priority: .utility) {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                do {
                    try newValue.write(to: saveURL, atomically: true, encoding: .utf8)
                } catch {
                    return
                }
                await MainActor.run {
                    savedIndicatorTask?.cancel()
                    savedIndicatorTask = Task {
                        savedIndicator = true
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { savedIndicator = false }
                    }
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
                }
                if isRunning {
                    ProgressView().controlSize(.small)
                    Button {
                        cancelExecution()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.callout)
                    }
                    .keyboardShortcut(".", modifiers: .command)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Cancel running query (⌘.)")
                }
                Button {
                    executeTask?.cancel()
                    executeTask = Task { await runCurrentQuery() }
                } label: {
                    Label("Run Current", systemImage: "play")
                        .font(.callout)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(client == nil || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                .help(client == nil ? "Select a connection above to run queries" : "")
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    executeTask?.cancel()
                    executeTask = Task { await runQuery() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.callout)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(client == nil || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                .help(client == nil ? "Select a connection above to run queries" : "")
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button {
                    executeTask?.cancel()
                    executeTask = Task { await explainCurrentQuery() }
                } label: {
                    Label("Explain", systemImage: "chart.bar.doc.horizontal")
                        .font(.callout)
                }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(client == nil || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                .help(client == nil ? "Select a connection above to run queries" : "EXPLAIN ANALYZE the current query")
                .buttonStyle(.bordered)
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
                // Hidden button for Cmd+/ toggle line comments
                Button(action: toggleLineComments) { EmptyView() }
                    .keyboardShortcut("/", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
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
                            executions = []
                            selectedResultTab = 0
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
            if !executions.isEmpty {
                resultTabBar
                Divider()
            }
            resultContent
        }
    }

    private var resultTabBar: some View {
        HStack(spacing: 2) {
            resultTabSegment("Log", index: 0)
            ForEach(Array(viewableTabs.enumerated()), id: \.element.entry.id) { n, tab in
                resultTabSegment(tab.label, index: n + 1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private func resultTabSegment(_ title: String, index: Int) -> some View {
        Button { selectedResultTab = index } label: {
            Text(title)
                .font(.system(size: contentFontSize - 1))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    selectedResultTab == index ? Color(nsColor: .selectedControlColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(selectedResultTab == index ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultContent: some View {
        if executions.isEmpty {
            Color(nsColor: .textBackgroundColor)
        } else if selectedResultTab == 0 {
            executionLog
        } else {
            let idx = selectedResultTab - 1
            if idx < viewableTabs.count {
                let entry = viewableTabs[idx].entry
                switch entry.outcome {
                case .rows(let r, let isCapped):
                    resultTabContent(result: r, isCapped: isCapped)
                case .explain(let er):
                    ExplainPlanView(result: er)
                default:
                    Color(nsColor: .textBackgroundColor)
                }
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
    }

    /// Unified ordered list of tabs that have a dedicated view (rows or explain plan).
    private var viewableTabs: [(label: String, entry: ExecutionEntry)] {
        var resultCount = 0
        var explainCount = 0
        return executions.compactMap { entry in
            switch entry.outcome {
            case .rows:
                resultCount += 1
                return ("Result \(resultCount)", entry)
            case .explain:
                explainCount += 1
                return ("Plan \(explainCount)", entry)
            default:
                return nil
            }
        }
    }

    // MARK: - Execution log

    private var executionLog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(executions) { entry in
                    executionLogRow(entry)
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func executionLogRow(_ entry: ExecutionEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("[\(entry.index)]")
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            Text(sqlPreview(entry.sql))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            logOutcomeView(entry)
        }
        .font(.system(size: contentFontSize - 1, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func logOutcomeView(_ entry: ExecutionEntry) -> some View {
        switch entry.outcome {
        case .running:
            ProgressView().controlSize(.mini)
        case .rows(let r, let isCapped):
            HStack(spacing: 6) {
                Text("\(r.rows.count) row\(r.rows.count == 1 ? "" : "s") · \(String(format: "%.3fs", r.duration))")
                    .foregroundStyle(.secondary)
                if isCapped {
                    Text("(capped)").foregroundStyle(.orange)
                }
                if let tabIdx = resultTabIndex(for: entry) {
                    Button("→ Result \(tabIdx)") { selectedResultTab = tabIdx }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                }
            }
        case .ok(let dur):
            Text("OK · \(String(format: "%.3fs", dur))")
                .foregroundStyle(.secondary)
        case .error(let msg):
            Text(msg)
                .foregroundStyle(.red)
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
        case .explain(let er):
            HStack(spacing: 6) {
                if let exec = er.executionMs {
                    Text(String(format: "%.3f ms", exec)).foregroundStyle(.secondary)
                } else {
                    Text(String(format: "%.3fs", er.duration)).foregroundStyle(.secondary)
                }
                if let tabIdx = viewableTabIndex(for: entry) {
                    Button("→ Plan \(tabIdx)") { selectedResultTab = tabIdx }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                }
            }
        case .cancelled:
            Text("Cancelled")
                .foregroundStyle(.secondary)
        }
    }

    private func sqlPreview(_ sql: String) -> String {
        let first = sql.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? sql
        let t = first.trimmingCharacters(in: .whitespaces)
        return t.count > 80 ? String(t.prefix(77)) + "…" : t
    }

    private func resultTabIndex(for entry: ExecutionEntry) -> Int? {
        viewableTabIndex(for: entry)
    }

    private func viewableTabIndex(for entry: ExecutionEntry) -> Int? {
        guard let idx = viewableTabs.firstIndex(where: { $0.entry.id == entry.id }) else { return nil }
        return idx + 1  // 1-based; 0 is the Log tab
    }

    // MARK: - Result tab content

    private func resultTabContent(result: QueryResult, isCapped: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(result.rows.count) row\(result.rows.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(String(format: "%.3fs", result.duration))
                    .font(.caption).foregroundStyle(.secondary)
                if isCapped {
                    Text("·").foregroundStyle(.tertiary)
                    Text("Showing first \(tuskPageSize) rows")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !result.rows.isEmpty {
                    Button {
                        copyRowsAsCSV(columns: result.columns, rows: result.rows)
                        copiedCSV = true
                        copiedCSVTask?.cancel()
                        copiedCSVTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedCSV = false } }
                    } label: {
                        Label(copiedCSV ? "Copied!" : "Copy CSV",
                              systemImage: copiedCSV ? "checkmark" : "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                    .help("Copy all rows as CSV")
                    Button {
                        copyRowsAsJSON(columns: result.columns, rows: result.rows)
                        copiedJSON = true
                        copiedJSONTask?.cancel()
                        copiedJSONTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedJSON = false } }
                    } label: {
                        Label(copiedJSON ? "Copied!" : "Copy JSON",
                              systemImage: copiedJSON ? "checkmark" : "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                    .help("Copy all rows as JSON")
                    Button {
                        exportCSV(result)
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up").font(.caption)
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()
            ResultsGrid(result: result)
        }
    }

    // MARK: - Run query

    private func runQuery() async {
        await execute(sql: sql)
    }

    private func runCurrentQuery() async {
        let nsSQL = sql as NSString
        let candidate: String
        if selectedRange.length > 0 {
            let safeLocation = min(selectedRange.location, nsSQL.length)
            let safeLength   = min(selectedRange.length, nsSQL.length - safeLocation)
            candidate = nsSQL.substring(with: NSRange(location: safeLocation, length: safeLength))
        } else {
            guard let found = statementAtCursor(in: sql, cursorLocation: selectedRange.location) else { return }
            candidate = found
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await execute(sql: trimmed)
    }

    private func persistResultStateToTab() {
        guard let index = appState.queryTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        appState.queryTabs[index].executions = executions
    }

    /// Shared execution engine used by both Run All and Run Current.
    /// Splits `sql` into statements, runs them sequentially, stops on first error.
    private func execute(sql: String) async {
        let liveConnectionID = appState.queryTabs.first(where: { $0.id == tab.id })?.connectionID
        guard let client = liveConnectionID.flatMap({ appState.clients[$0] }) else { return }

        let statements = splitStatements(sql)
        guard !statements.isEmpty else { return }

        executions = []
        selectedResultTab = 0
        isRunning = true
        persistResultStateToTab()

        for stmt in statements {
            guard !Task.isCancelled else {
                isRunning = false
                persistResultStateToTab()
                return
            }
            let idx = executions.count + 1
            executions.append(ExecutionEntry(index: idx, sql: stmt, outcome: .running))
            let entryIndex = executions.count - 1

            let (finalSQL, capped) = cappedSQL(stmt)
            do {
                let r = try await client.query(finalSQL, rowLimit: tuskPageSize)
                // If Stop was pressed while the query was running, discard the result.
                guard !Task.isCancelled else {
                    executions[entryIndex].outcome = .cancelled
                    isRunning = false
                    persistResultStateToTab()
                    return
                }
                if !capped && r.columns.isEmpty {
                    executions[entryIndex].outcome = .ok(duration: r.duration)
                } else {
                    executions[entryIndex].outcome = .rows(r, isCapped: capped && r.rows.count == tuskPageSize)
                }
            } catch is CancellationError {
                executions[entryIndex].outcome = .cancelled
                isRunning = false
                persistResultStateToTab()
                return
            } catch {
                // pg_cancel_backend delivers the cancel as a server error, not CancellationError.
                // Treat any error on a cancelled task as cancelled.
                if Task.isCancelled {
                    executions[entryIndex].outcome = .cancelled
                    isRunning = false
                    persistResultStateToTab()
                    return
                }
                executions[entryIndex].outcome = .error(error.localizedDescription)
                break
            }
        }

        isRunning = false

        // Auto-refresh schema if any DDL statement succeeded
        let ddlPrefixes = ["CREATE", "DROP", "ALTER"]
        let hasDDL = executions.contains { entry in
            guard case .ok = entry.outcome else { return false }
            let prefix = entry.sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return ddlPrefixes.contains { prefix.hasPrefix($0) }
        }
        if hasDDL,
           let connID = liveConnectionID,
           let connection = appState.connections.first(where: { $0.id == connID }) {
            Task { try? await appState.refreshSchema(for: connection) }
        }

        // Auto-switch to Result 1 for the common single-SELECT-no-error case
        let hasError = executions.contains { if case .error = $0.outcome { true } else { false } }
        let resultCount = executions.filter { if case .rows = $0.outcome { true } else { false } }.count
        if resultCount == 1 && !hasError { selectedResultTab = 1 }

        persistResultStateToTab()
    }

    // MARK: - Explain

    private func explainCurrentQuery() async {
        let nsSQL = sql as NSString
        let candidate: String
        if selectedRange.length > 0 {
            let safeLocation = min(selectedRange.location, nsSQL.length)
            let safeLength   = min(selectedRange.length, nsSQL.length - safeLocation)
            candidate = nsSQL.substring(with: NSRange(location: safeLocation, length: safeLength))
        } else {
            guard let found = statementAtCursor(in: sql, cursorLocation: selectedRange.location) else { return }
            candidate = found
        }
        let stmts = splitStatements(candidate)
        guard stmts.count == 1 else {
            executions = [ExecutionEntry(index: 1, sql: candidate,
                                         outcome: .error(stmts.isEmpty
                                             ? "Nothing to explain"
                                             : "Explain requires exactly one statement — select a single statement"))]
            selectedResultTab = 0
            return
        }
        let (clean, _) = cappedSQL(stmts[0])
        await executeExplain(sql: clean)
    }

    private func executeExplain(sql: String) async {
        let liveConnectionID = appState.queryTabs.first(where: { $0.id == tab.id })?.connectionID
        guard let client = liveConnectionID.flatMap({ appState.clients[$0] }) else { return }

        executions = []
        selectedResultTab = 0
        isRunning = true
        persistResultStateToTab()

        let idx = 1
        executions.append(ExecutionEntry(index: idx, sql: sql, outcome: .running))

        let explainSQL = "EXPLAIN (FORMAT JSON, ANALYZE, BUFFERS) \(sql)"
        do {
            let r = try await client.query(explainSQL)
            guard !Task.isCancelled else {
                executions[0].outcome = .cancelled
                isRunning = false
                persistResultStateToTab()
                return
            }
            if let jsonText = r.rows.first?.first.flatMap({ if case .text(let s) = $0 { return s }; return nil }),
               let er = ExplainResult.parse(jsonText: jsonText, duration: r.duration) {
                executions[0].outcome = .explain(er)
            } else {
                executions[0].outcome = .error("Could not parse EXPLAIN output")
            }
        } catch is CancellationError {
            executions[0].outcome = .cancelled
            isRunning = false
            persistResultStateToTab()
            return
        } catch {
            if Task.isCancelled {
                executions[0].outcome = .cancelled
                isRunning = false
                persistResultStateToTab()
                return
            }
            executions[0].outcome = .error(error.localizedDescription)
        }

        isRunning = false
        // Auto-switch to the plan tab
        if case .explain = executions[0].outcome { selectedResultTab = 1 }
        persistResultStateToTab()
    }

    // MARK: - Cancel execution

    private func cancelExecution() {
        executeTask?.cancel()
        executeTask = nil
        // Mark any still-running entries as cancelled and clear the spinner immediately.
        for i in executions.indices {
            if case .running = executions[i].outcome {
                executions[i].outcome = .cancelled
            }
        }
        isRunning = false
        persistResultStateToTab()
        // Signal PostgreSQL to cancel the backend query so the actor connection is
        // unblocked — use the view's direct client reference rather than looking up
        // through appState.queryTabs (which may already be removed on tab close).
        if let client {
            Task { await client.cancelCurrentQuery() }
        }
    }

    // MARK: - Toggle line comments

    /// Toggles `-- ` prefix on all lines touched by the current selection (or the cursor line).
    /// If every affected line already begins with `-- `, removes the prefix; otherwise adds it.
    private func toggleLineComments() {
        let nsSQL = sql as NSString
        let len = nsSQL.length
        guard len > 0 else { return }

        // Determine the character range covering all selected (or cursor) lines.
        let selLoc    = min(selectedRange.location, len)
        let selEnd    = min(selLoc + selectedRange.length, len)
        let lineStart = nsSQL.lineRange(for: NSRange(location: selLoc, length: 0)).location
        let lineEnd   = nsSQL.lineRange(for: NSRange(location: max(selLoc, selEnd > 0 ? selEnd - 1 : selEnd), length: 0))
        let coverRange = NSRange(location: lineStart, length: NSMaxRange(lineEnd) - lineStart)

        // Collect the individual line ranges within that span.
        var lineRanges: [NSRange] = []
        var pos = coverRange.location
        while pos < NSMaxRange(coverRange) {
            let lr = nsSQL.lineRange(for: NSRange(location: pos, length: 0))
            lineRanges.append(lr)
            let next = NSMaxRange(lr)
            if next <= pos { break }
            pos = next
        }
        guard !lineRanges.isEmpty else { return }

        // Decide: uncomment if every non-empty line already starts with "--".
        let nonEmpty = lineRanges.filter { r in
            let line = nsSQL.substring(with: r)
            return !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy { r in
            nsSQL.substring(with: r).hasPrefix("--")
        }

        // Compute per-line deltas to adjust the selection after mutation.
        // Each delta is +3 (add "-- "), -3 (remove "-- "), or -2 (remove "--").
        var lineDeltas: [Int] = lineRanges.map { lr in
            if allCommented {
                let line = nsSQL.substring(with: lr)
                return line.hasPrefix("-- ") ? -3 : (line.hasPrefix("--") ? -2 : 0)
            } else {
                return 3
            }
        }

        // Build the new string by mutating line by line (process in reverse to keep ranges valid).
        var mutSQL = sql
        for (i, lr) in lineRanges.enumerated().reversed() {
            let line = nsSQL.substring(with: lr)
            guard let swiftRange = Range(lr, in: mutSQL) else { lineDeltas[i] = 0; continue }
            if allCommented {
                if line.hasPrefix("-- ") {
                    mutSQL.replaceSubrange(swiftRange, with: line.replacingCharacters(in: line.startIndex..<line.index(line.startIndex, offsetBy: 3), with: ""))
                } else if line.hasPrefix("--") {
                    mutSQL.replaceSubrange(swiftRange, with: line.replacingCharacters(in: line.startIndex..<line.index(line.startIndex, offsetBy: 2), with: ""))
                }
            } else {
                mutSQL.replaceSubrange(swiftRange, with: "-- " + line)
            }
        }

        // Adjust selectedRange: sum deltas for lines whose start is at or before selLoc/selEnd.
        var locDelta = 0
        var endDelta = 0
        for (idx, lr) in lineRanges.enumerated() {
            if lr.location <= selLoc { locDelta += lineDeltas[idx] }
            if lr.location < selEnd  { endDelta += lineDeltas[idx] }
        }
        let newLen    = (mutSQL as NSString).length
        let newLoc    = max(0, min(selLoc + locDelta, newLen))
        let rawEnd    = selEnd + endDelta
        let newSelLen = max(0, min(rawEnd, newLen) - newLoc)
        sql = mutSQL
        selectedRange = NSRange(location: newLoc, length: newSelLen)
    }

    // MARK: - Statement splitting

    /// Splits `sql` into trimmed statements using the same quote-aware state
    /// machine as `statementAtCursor`. Empty segments are excluded.
    private func splitStatements(_ sql: String) -> [String] {
        let ns  = sql as NSString
        let len = ns.length
        guard len > 0 else { return [] }

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

        var results: [String] = []
        var state: State = .normal
        var stmtStart = 0
        var i = 0

        func flush() {
            let s = ns.substring(with: NSRange(location: stmtStart, length: i - stmtStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { results.append(s) }
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
                    } else { i += 1 }
                } else if ch == semicolon {
                    flush(); stmtStart = i + 1; i += 1
                } else { i += 1 }

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

        flush()
        return results
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

        // Cursor is in the final segment (no trailing semicolon).
        // Guard: cursor must be at or after the first actual content character —
        // not just in leading whitespace or comments before the next statement.
        guard cursor >= stmtStart else { return nil }
        var ci = stmtStart
        while ci < len {
            let c  = ns.character(at: ci)
            let n2 = ci + 1 < len ? ns.character(at: ci + 1) : 0
            if c == 32 || c == 9 || c == 10 || c == 13 {
                ci += 1
            } else if c == hyphen && n2 == hyphen {
                ci += 2
                while ci < len && ns.character(at: ci) != newline && ns.character(at: ci) != cr { ci += 1 }
            } else if c == slash && n2 == asterisk {
                ci += 2
                while ci + 1 < len && !(ns.character(at: ci) == asterisk && ns.character(at: ci + 1) == slash) { ci += 1 }
                ci += 2
            } else { break }
        }
        guard cursor >= ci else { return nil }
        return stmtSubstring()
    }
}

// MARK: - Results grid

struct ResultsGrid: View {
    let result: QueryResult
    /// When provided, column widths are persisted to UserDefaults under this key.
    var columnWidthsPersistenceKey: String? = nil
    /// When provided, pinned column names are persisted to UserDefaults under this key.
    var pinnedColumnsPersistenceKey: String? = nil
    var copyAsInsert: (([[QueryCell]]) -> Void)? = nil
    /// Schema column metadata — when provided with `onExecuteSQL`, enables edit/delete.
    var tableColumns: [ColumnInfo] = []
    /// Qualified table name (e.g. `"public"."users"`) used in generated SQL.
    var qualifiedTableName: String = ""
    /// Called with a SQL string (UPDATE or DELETE) to execute and refresh.
    var onExecuteSQL: ((String) async throws -> Void)? = nil
    /// Currently active sort column name — when provided, enables sort indicators.
    var sortColumn: String? = nil
    /// Current sort direction — true = ASC.
    var sortAscending: Bool = true
    /// Called when user taps a column header to sort. Nil disables sorting UI.
    var onSortByColumn: ((String) -> Void)? = nil

    @State private var expandedCell: CellDetailContent? = nil
    @State private var selectedRows: Set<Int> = []
    @State private var lastSelectedRow: Int? = nil
    @FocusState private var isFocused: Bool
    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var keyboardCursor: Int? = nil

    // Column resizing
    private let defaultColumnWidth: CGFloat = 150
    @State private var columnWidths: [Int: CGFloat] = [:]
    @State private var dragStartWidths: [Int: CGFloat] = [:]

    // Pinned columns
    @State private var pinnedColumns: Set<String> = []
    @State private var syncedRow: Int? = nil

    private func columnWidth(_ colIndex: Int) -> CGFloat {
        columnWidths[colIndex] ?? defaultColumnWidth
    }

    private func loadPersistedWidths() {
        guard let key = columnWidthsPersistenceKey,
              let data = UserDefaults.standard.data(forKey: key),
              let named = try? JSONDecoder().decode([String: CGFloat].self, from: data)
        else { return }
        for (colIndex, col) in result.columns.enumerated() {
            if let w = named[col.name] { columnWidths[colIndex] = w }
        }
    }

    private func persistWidths() {
        guard let key = columnWidthsPersistenceKey else { return }
        var named: [String: CGFloat] = [:]
        for (colIndex, col) in result.columns.enumerated() {
            if let w = columnWidths[colIndex] { named[col.name] = w }
        }
        if let data = try? JSONEncoder().encode(named) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private var pinnedColIndices: [Int] {
        result.columns.indices.filter { pinnedColumns.contains(result.columns[$0].name) }
    }

    private var nonPinnedColIndices: [Int] {
        result.columns.indices.filter { !pinnedColumns.contains(result.columns[$0].name) }
    }

    private var totalPinnedWidth: CGFloat {
        pinnedColIndices.reduce(0) { $0 + columnWidth($1) }
    }

    private func loadPersistedPinnedColumns() {
        guard let key = pinnedColumnsPersistenceKey else { return }
        let valid = Set(result.columns.map(\.name))
        if let names = UserDefaults.standard.stringArray(forKey: key) {
            let cleaned = Set(names).intersection(valid)
            pinnedColumns = cleaned
            // Prune stale entries so they don't accumulate in UserDefaults.
            if cleaned.count != names.count {
                UserDefaults.standard.set(Array(cleaned), forKey: key)
            }
        } else {
            pinnedColumns = []
        }
    }

    private func persistPinnedColumns() {
        guard let key = pinnedColumnsPersistenceKey else { return }
        UserDefaults.standard.set(Array(pinnedColumns), forKey: key)
    }

    // Edit-cell sheet state
    @State private var editingRowIndex: Int? = nil
    @State private var editingColIndex: Int? = nil
    @State private var editingText: String = ""
    @State private var editingIsNull: Bool = false
    @State private var isSavingEdit = false
    @State private var editError: String? = nil

    // Delete confirmation state
    @State private var deletingRowIndex: Int? = nil
    @State private var isDeletingRow = false
    @State private var deleteError: String? = nil

    /// True when the table has at least one primary-key column and we have an executor.
    private var canEdit: Bool {
        onExecuteSQL != nil && tableColumns.contains { $0.isPrimaryKey }
    }

    private var primaryKeyColumns: [ColumnInfo] {
        tableColumns.filter { $0.isPrimaryKey }
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if !pinnedColIndices.isEmpty, pinnedColumnsPersistenceKey != nil {
                    twoPaneLayout(geo: geo)
                } else {
                    singlePaneLayout(geo: geo)
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
        .sheet(isPresented: Binding(get: { editingRowIndex != nil }, set: { if !$0 { clearEditing() } })) {
            EditCellSheet(
                columnName: editingColName,
                text: $editingText,
                isNull: $editingIsNull,
                isSaving: isSavingEdit,
                error: editError,
                onSave: { await commitEdit() },
                onCancel: { clearEditing() }
            )
        }
        .alert("Delete Row?", isPresented: Binding(get: { deletingRowIndex != nil }, set: { if !$0 { deletingRowIndex = nil } })) {
            Button("Delete", role: .destructive) {
                if let rowIndex = deletingRowIndex {
                    Task { await commitDelete(rowIndex: rowIndex) }
                }
            }
            Button("Cancel", role: .cancel) { deletingRowIndex = nil }
        } message: {
            Text("This will permanently delete the row from the database.")
        }
        .alert("Delete Failed", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .onChange(of: result.id) {
            selectedRows.removeAll()
            lastSelectedRow = nil
            keyboardCursor = nil
            syncedRow = nil
        }
        .onChange(of: columnWidthsPersistenceKey) { _, _ in
            columnWidths = [:]
            pinnedColumns = []
            loadPersistedWidths()
            loadPersistedPinnedColumns()
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func singlePaneLayout(geo: GeometryProxy) -> some View {
        ScrollView([.horizontal, .vertical]) {
            ScrollViewReader { proxy in
                let allIndices = Array(result.columns.indices)
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(result.rows.indices, id: \.self) { rowIndex in
                            dataRow(rowIndex: rowIndex, colIndices: allIndices)
                        }
                    } header: {
                        headerRow(colIndices: allIndices)
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                .onAppear {
                    scrollProxy = proxy
                    loadPersistedWidths()
                    loadPersistedPinnedColumns()
                }
            }
        }
    }

    @ViewBuilder
    private func twoPaneLayout(geo: GeometryProxy) -> some View {
        let pinnedIndices = pinnedColIndices
        let nonPinnedIndices = nonPinnedColIndices
        let leftWidth = totalPinnedWidth

        HStack(spacing: 0) {
            // Left pane — pinned columns, vertical scroll only
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(result.rows.indices, id: \.self) { rowIndex in
                            dataRow(rowIndex: rowIndex, colIndices: pinnedIndices)
                        }
                    } header: {
                        headerRow(colIndices: pinnedIndices)
                    }
                }
                .frame(minHeight: geo.size.height, alignment: .topLeading)
            }
            .frame(width: leftWidth)
            .scrollPosition(id: $syncedRow)

            if !nonPinnedIndices.isEmpty {
                // Pinned / scrollable separator
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 2)

                // Right pane — non-pinned columns, scrolls both ways
                ScrollView([.horizontal, .vertical]) {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(result.rows.indices, id: \.self) { rowIndex in
                                    dataRow(rowIndex: rowIndex, colIndices: nonPinnedIndices)
                                }
                            } header: {
                                headerRow(colIndices: nonPinnedIndices)
                            }
                        }
                        .frame(minWidth: max(0, geo.size.width - leftWidth - 2), minHeight: geo.size.height, alignment: .topLeading)
                        .onAppear {
                            scrollProxy = proxy
                        }
                    }
                }
                .scrollPosition(id: $syncedRow)
            }
        }
    }

    @ViewBuilder
    private func dataRow(rowIndex: Int, colIndices: [Int]) -> some View {
        let row = result.rows[rowIndex]
        let isSelected = selectedRows.contains(rowIndex)
        HStack(spacing: 0) {
            ForEach(colIndices, id: \.self) { colIndex in
                let cell = row[colIndex]
                cellText(cell)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(width: columnWidth(colIndex), alignment: .leading)
                    .border(Color(nsColor: .separatorColor), width: 0.5)
                    .onTapGesture(count: 2) {
                        if canEdit {
                            startEditing(rowIndex: rowIndex, colIndex: colIndex, cell: cell)
                        } else {
                            let dtype = colIndex < result.columns.count ? result.columns[colIndex].dataType : ""
                            expandedCell = CellDetailContent(id: "\(rowIndex):\(colIndex)", value: cell.displayValue, columnDataType: dtype)
                        }
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
                        if canEdit {
                            Divider()
                            Button("Edit Cell…") {
                                startEditing(rowIndex: rowIndex, colIndex: colIndex, cell: cell)
                            }
                        }
                    }
            }
        }
        .id(rowIndex)
        .background(rowBackground(rowIndex: rowIndex, isSelected: isSelected))
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard value.translation == .zero else { return }
                    guard !NSEvent.modifierFlags.contains(.control) else { return }
                    isFocused = true
                    handleRowTap(rowIndex: rowIndex)
                }
        )
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
            if canEdit {
                Divider()
                Button("Delete Row…", role: .destructive) {
                    deletingRowIndex = rowIndex
                }
            }
        }
    }

    @ViewBuilder
    private func headerRow(colIndices: [Int]) -> some View {
        HStack(spacing: 0) {
            ForEach(colIndices, id: \.self) { colIndex in
                headerCell(colIndex: colIndex)
            }
        }
    }

    @ViewBuilder
    private func headerCell(colIndex: Int) -> some View {
        let col = result.columns[colIndex]
        let isActiveSort = sortColumn == col.name
        let isPinned = pinnedColumns.contains(col.name)
        ZStack(alignment: .trailing) {
            HStack(spacing: 4) {
                Text(col.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isActiveSort {
                    Text(sortAscending ? "↑" : "↓")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: columnWidth(colIndex), alignment: .leading)
            .background {
                if isPinned {
                    Color(nsColor: .controlBackgroundColor).brightness(-0.04)
                } else {
                    Color(nsColor: .controlBackgroundColor)
                }
            }
            .border(Color(nsColor: .separatorColor), width: 0.5)
            .contentShape(Rectangle())
            .onTapGesture {
                onSortByColumn?(col.name)
            }
            .onHover { inside in
                if onSortByColumn != nil {
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }

            // Drag handle on right edge
            Color.clear
                .frame(width: 6)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartWidths[colIndex] == nil {
                                dragStartWidths[colIndex] = columnWidth(colIndex)
                            }
                            let startWidth = dragStartWidths[colIndex]!
                            columnWidths[colIndex] = max(50, startWidth + value.translation.width)
                        }
                        .onEnded { _ in
                            dragStartWidths.removeValue(forKey: colIndex)
                            persistWidths()
                        }
                )
        }
        .contextMenu {
            if pinnedColumnsPersistenceKey != nil {
                if isPinned {
                    Button("Unpin Column") {
                        pinnedColumns.remove(col.name)
                        persistPinnedColumns()
                    }
                } else {
                    Button("Pin Column") {
                        pinnedColumns.insert(col.name)
                        persistPinnedColumns()
                    }
                }
            }
        }
    }

    // MARK: - Edit helpers

    private var editingColName: String {
        guard let c = editingColIndex, c < result.columns.count else { return "" }
        return result.columns[c].name
    }

    private func startEditing(rowIndex: Int, colIndex: Int, cell: QueryCell) {
        // Binary data cannot be round-tripped through a text field — skip silently.
        if case .bytes = cell { return }
        editingRowIndex = rowIndex
        editingColIndex = colIndex
        editingIsNull = cell.isNull
        editingText = cell.isNull ? "" : cell.displayValue
        editError = nil
    }

    private func clearEditing() {
        editingRowIndex = nil
        editingColIndex = nil
        editingText = ""
        editingIsNull = false
        isSavingEdit = false
        editError = nil
    }

    private func commitEdit() async {
        guard let rowIndex = editingRowIndex,
              let colIndex = editingColIndex,
              rowIndex < result.rows.count,
              colIndex < result.columns.count,
              let execute = onExecuteSQL else { return }

        let colName = result.columns[colIndex].name
        let newValueSQL = editingIsNull ? "NULL" : "'\(editingText.replacingOccurrences(of: "'", with: "''"))'"
        guard let whereClause = buildWhereClause(row: result.rows[rowIndex]) else {
            editError = "Cannot update: one or more primary key columns are missing from the result."
            return
        }

        let sql = "UPDATE \(qualifiedTableName) SET \(quoteIdentifier(colName)) = \(newValueSQL) WHERE \(whereClause)"

        isSavingEdit = true
        editError = nil
        do {
            try await execute(sql)
            clearEditing()
        } catch {
            isSavingEdit = false
            editError = error.localizedDescription
        }
    }

    private func commitDelete(rowIndex: Int) async {
        guard rowIndex < result.rows.count, let execute = onExecuteSQL else { return }
        guard let whereClause = buildWhereClause(row: result.rows[rowIndex]) else {
            deleteError = "Cannot delete: one or more primary key columns are missing from the result."
            deletingRowIndex = nil
            return
        }
        let sql = "DELETE FROM \(qualifiedTableName) WHERE \(whereClause)"
        isDeletingRow = true
        do {
            try await execute(sql)
        } catch {
            deleteError = error.localizedDescription
        }
        isDeletingRow = false
        deletingRowIndex = nil
    }

    /// Builds `"pk1" = val1 AND "pk2" = val2` using the primary-key columns.
    /// Returns `nil` if any PK column is absent from the result — callers must treat this as an error
    /// rather than executing a potentially under-constrained WHERE clause.
    private func buildWhereClause(row: [QueryCell]) -> String? {
        let pkCols = primaryKeyColumns
        var parts: [String] = []
        for pkCol in pkCols {
            guard let resultColIndex = result.columns.firstIndex(where: { $0.name == pkCol.name }),
                  resultColIndex < row.count else { return nil }
            let cell = row[resultColIndex]
            parts.append("\(quoteIdentifier(pkCol.name)) = \(sqlLiteralForWhere(cell))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " AND ")
    }

    private func sqlLiteralForWhere(_ cell: QueryCell) -> String {
        switch cell {
        case .null:            return "NULL"
        case .text(let s):     return "'\(s.replacingOccurrences(of: "'", with: "''"))'"
        case .integer(let i):  return String(i)
        case .double(let d):   return String(d)
        case .bool(let b):     return b ? "TRUE" : "FALSE"
        case .bytes(let data): return "'\\x\(data.map { String(format: "%02x", $0) }.joined())'"
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

        if pinnedColumns.isEmpty || pinnedColumnsPersistenceKey == nil {
            scrollProxy?.scrollTo(newCursor, anchor: .center)
        } else {
            syncedRow = newCursor
        }
    }

    private func handleSelectAll() {
        guard !result.rows.isEmpty else { return }
        selectedRows = Set(result.rows.indices)
        lastSelectedRow = 0
        keyboardCursor = 0
        if pinnedColumns.isEmpty || pinnedColumnsPersistenceKey == nil {
            scrollProxy?.scrollTo(0, anchor: .top)
        } else {
            syncedRow = 0
        }
    }
}

// MARK: - Edit cell sheet

private struct EditCellSheet: View {
    let columnName: String
    @Binding var text: String
    @Binding var isNull: Bool
    let isSaving: Bool
    let error: String?
    let onSave: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit \"\(columnName)\"")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await onSave() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding()

            Divider()

            Form {
                Section {
                    Toggle("Set to NULL", isOn: $isNull)
                    if !isNull {
                        TextField("Value", text: $text, axis: .vertical)
                            .lineLimit(5...10)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .formStyle(.grouped)

            if let err = error {
                Divider()
                HStack {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding()
            }

            if isSaving {
                Divider()
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Saving…").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            }
        }
        .frame(width: 380)
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
    @State private var cachedPrettyJSON: String? = nil

    private var parsedJSON: JSONValue? {
        guard columnDataType == "json" || columnDataType == "jsonb" else { return nil }
        return parseJSONValue(value)
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
                let displayText = json != nil ? (cachedPrettyJSON ?? value) : value
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
        .onAppear {
            guard columnDataType == "json" || columnDataType == "jsonb" else { return }
            guard let data = value.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                  let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                  let str = String(data: pretty, encoding: .utf8)
            else { return }
            cachedPrettyJSON = str
        }
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
