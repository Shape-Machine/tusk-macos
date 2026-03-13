import SwiftUI

struct DataBrowserView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String

    private var qualifiedName: String { "\"\(schemaName)\".\"\(tableName)\"" }

    @State private var result: QueryResult? = nil
    @State private var error: String? = nil
    @State private var isLoading = false
    @State private var pageSize = 200
    @State private var offset = 0
    @State private var sortColumn: String? = nil
    @State private var sortAscending = true
    @State private var filterText = ""
    @State private var filterTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result {
                VStack(spacing: 0) {
                    if result.rows.isEmpty {
                        ContentUnavailableView("Empty Table", systemImage: "tray",
                            description: Text("This table has no data."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ResultsGrid(result: result)
                    }
                    Divider()
                    statusBar(result: result)
                }
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
        .task { await load() }
        .onChange(of: tableName) { _, _ in
            offset = 0
            Task { await load() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Spacer()

            TextField("Filter…", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onChange(of: filterText) { _, _ in
                    filterTask?.cancel()
                    filterTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        offset = 0
                        await load()
                    }
                }

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Status bar

    private func statusBar(result: QueryResult) -> some View {
        HStack {
            Text("\(result.rows.count) rows")
                .font(.caption)
                .foregroundStyle(.secondary)

            if offset > 0 {
                Button("← Previous") {
                    offset = max(0, offset - pageSize)
                    Task { await load() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if result.rows.count == pageSize {
                Button("Next →") {
                    offset += pageSize
                    Task { await load() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Spacer()

            Button {
                exportCSV(result)
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        error = nil

        var sql = "SELECT * FROM \(qualifiedName)"

        if !filterText.isEmpty {
            sql += " WHERE \(qualifiedName)::text ILIKE '%\(filterText)%'"
        }

        if let col = sortColumn {
            sql += " ORDER BY \"\(col)\" \(sortAscending ? "ASC" : "DESC")"
        }

        sql += " LIMIT \(pageSize) OFFSET \(offset)"

        do {
            result = try await client.query(sql)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Export

    private func exportCSV(_ result: QueryResult) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(tableName).csv"
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
