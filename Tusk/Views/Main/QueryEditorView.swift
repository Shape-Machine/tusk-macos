import SwiftUI

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
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

            // Results pane
            resultsPane
                .frame(minHeight: 100)
        }
        .onAppear { sql = tab.sql }
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
                if client != nil {
                    Text(tab.connectionName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("No connection", systemImage: "bolt.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                SQLTextEditor(text: $sql)
                if sql.isEmpty {
                    Text("-- Write SQL here · ⌘↵ to run")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
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
        guard let client else { return }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isRunning = true
        error = nil
        result = nil
        resultIsCapped = false

        let (finalSQL, capped) = cappedSQL(trimmed)
        do {
            let r = try await client.query(finalSQL, rowLimit: tuskPageSize)
            result = r
            resultIsCapped = capped && r.rows.count == tuskPageSize
        } catch {
            self.error = error.localizedDescription
        }

        isRunning = false
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "query_result.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = [result.columns.map(\.name).joined(separator: ",")]
        for row in result.rows {
            lines.append(row.map { cell in
                let val = cell.displayValue
                return val.contains(",") || val.contains("\n") ? "\"\(val)\"" : val
            }.joined(separator: ","))
        }

        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Results grid

struct ResultsGrid: View {
    let result: QueryResult

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    // Header row
                    GridRow {
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

                    // Data rows
                    ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                                Text(cell.displayValue)
                                    .foregroundStyle(cell.isNull ? .tertiary : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                    .background(rowIndex.isMultiple(of: 2)
                                        ? Color(nsColor: .controlAlternatingRowBackgroundColors[0])
                                        : Color(nsColor: .controlAlternatingRowBackgroundColors[1]))
                                    .border(Color(nsColor: .separatorColor), width: 0.5)
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(cell.displayValue, forType: .string)
                                        }
                                    }
                            }
                        }
                    }
                }
                .frame(
                    minWidth: geo.size.width,
                    minHeight: geo.size.height,
                    alignment: .topLeading
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
