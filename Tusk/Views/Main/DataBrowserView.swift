import SwiftUI

// MARK: - Data browser state (survives sub-tab switches)

@MainActor
@Observable
final class DataBrowserState {
    var result: QueryResult? = nil
    var isLoading: Bool = false
    var error: String? = nil
    var offset: Int = 0
    var filterText: String = ""
    var loadTask: Task<Void, Never>? = nil
    var filterDebounceTask: Task<Void, Never>? = nil
}

// MARK: - Data browser view

struct DataBrowserView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String
    var isView: Bool = false
    @Bindable var state: DataBrowserState

    private var qualifiedName: String { "\"\(schemaName)\".\"\(tableName)\"" }
    private let pageSize = tuskPageSize

    @State private var sortColumn: String? = nil
    @State private var sortAscending = true
    @State private var copiedInsert = false
    @State private var copiedInsertTask: Task<Void, Never>? = nil
    @State private var copiedCSV = false
    @State private var copiedCSVTask: Task<Void, Never>? = nil
    @State private var copiedJSON = false
    @State private var copiedJSONTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if state.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.error {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = state.result {
                VStack(spacing: 0) {
                    if result.rows.isEmpty {
                        ContentUnavailableView("Empty Table", systemImage: "tray",
                            description: Text("This table has no data."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ResultsGrid(result: result, copyAsInsert: isView ? nil : { rows in
                            copyRowsAsInsert(schema: schemaName, table: tableName, columns: result.columns, rows: rows)
                        })
                    }
                    Divider()
                    statusBar(result: result)
                }
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
        .task { if state.result == nil { triggerLoad() } }
        .onChange(of: schemaName + "." + tableName) { _, _ in
            state.offset = 0
            triggerLoad()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Spacer()

            ZStack(alignment: .trailing) {
                TextField("Filter…", text: $state.filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                if state.isLoading && !state.filterText.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.trailing, 6)
                }
            }
            .frame(width: 180)
            .onChange(of: state.filterText) { _, _ in
                    state.filterDebounceTask?.cancel()
                    state.filterDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        state.offset = 0
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

            if state.offset > 0 {
                Button("← Previous") {
                    state.offset = max(0, state.offset - pageSize)
                    triggerLoad()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if result.rows.count == pageSize {
                Button("Next →") {
                    state.offset += pageSize
                    triggerLoad()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Spacer()

            if !isView {
                Button {
                    copyRowsAsInsert(schema: schemaName, table: tableName, columns: result.columns, rows: result.rows)
                    copiedInsert = true
                    copiedInsertTask?.cancel()
                    copiedInsertTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedInsert = false } }
                } label: {
                    Label(copiedInsert ? "Copied!" : "Copy INSERT",
                          systemImage: copiedInsert ? "checkmark" : "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy all rows as INSERT statements")
            }
            Button {
                copyRowsAsCSV(columns: result.columns, rows: result.rows)
                copiedCSV = true
                copiedCSVTask?.cancel()
                copiedCSVTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedCSV = false } }
            } label: {
                Label(copiedCSV ? "Copied!" : "Copy CSV",
                      systemImage: copiedCSV ? "checkmark" : "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy all rows as CSV")
            Button {
                copyRowsAsJSON(columns: result.columns, rows: result.rows)
                copiedJSON = true
                copiedJSONTask?.cancel()
                copiedJSONTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedJSON = false } }
            } label: {
                Label(copiedJSON ? "Copied!" : "Copy JSON",
                      systemImage: copiedJSON ? "checkmark" : "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy all rows as JSON")
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
        state.loadTask?.cancel()
        state.loadTask = Task { await load() }
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        state.isLoading = true
        state.error = nil
        // Only clear isLoading when this task was not superseded by a newer one.
        defer { if !Task.isCancelled { state.isLoading = false } }

        var sql = "SELECT * FROM \(qualifiedName)"

        if !state.filterText.isEmpty {
            sql += " WHERE \"\(tableName)\"::text ILIKE '%\(state.filterText)%'"
        }

        if let col = sortColumn {
            sql += " ORDER BY \"\(col)\" \(sortAscending ? "ASC" : "DESC")"
        }

        sql += " LIMIT \(pageSize) OFFSET \(state.offset)"

        do {
            let queryResult = try await client.query(sql)
            guard !Task.isCancelled else { return }
            state.result = queryResult
        } catch is CancellationError {
            // A newer load superseded this one — don't touch the visible state.
            return
        } catch {
            guard !Task.isCancelled else { return }
            state.error = error.localizedDescription
        }
    }

    // MARK: - Export

    private func exportCSV(_ result: QueryResult) {
        exportResultAsCSV(result, defaultName: tableName)
    }
}
