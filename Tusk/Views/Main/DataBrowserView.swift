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
    private let pageSize = tuskPageSize
    @State private var offset = 0
    @State private var sortColumn: String? = nil
    @State private var sortAscending = true
    @State private var filterText = ""
    @State private var filterDebounceTask: Task<Void, Never>? = nil
    @State private var loadTask: Task<Void, Never>? = nil

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
        .task { triggerLoad() }
        .onChange(of: tableName) { _, _ in
            offset = 0
            triggerLoad()
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
                    filterDebounceTask?.cancel()
                    filterDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        offset = 0
                        triggerLoad()
                    }
                }

            Button {
                triggerLoad()
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
                    triggerLoad()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if result.rows.count == pageSize {
                Button("Next →") {
                    offset += pageSize
                    triggerLoad()
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

    /// Cancels any in-flight load and starts a fresh one.
    private func triggerLoad() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        isLoading = true
        error = nil
        // Only clear isLoading when this task was not superseded by a newer one.
        defer { if !Task.isCancelled { isLoading = false } }

        var sql = "SELECT * FROM \(qualifiedName)"

        if !filterText.isEmpty {
            sql += " WHERE \(qualifiedName)::text ILIKE '%\(filterText)%'"
        }

        if let col = sortColumn {
            sql += " ORDER BY \"\(col)\" \(sortAscending ? "ASC" : "DESC")"
        }

        sql += " LIMIT \(pageSize) OFFSET \(offset)"

        do {
            let queryResult = try await client.query(sql)
            guard !Task.isCancelled else { return }
            result = queryResult
        } catch is CancellationError {
            // A newer load superseded this one — don't touch the visible state.
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    // MARK: - Export

    private func exportCSV(_ result: QueryResult) {
        exportResultAsCSV(result, defaultName: tableName)
    }
}
