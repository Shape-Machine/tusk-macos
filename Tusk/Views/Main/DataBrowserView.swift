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
    var filterColumn: String? = nil
    var loadTask: Task<Void, Never>? = nil
    var filterDebounceTask: Task<Void, Never>? = nil

    // Row count display (#200)
    var estimatedRowCount: Int64? = nil
    var filteredRowCount: Int64? = nil
    var isLoadingFilteredCount = false
    var countTask: Task<Void, Never>? = nil
}

// MARK: - Data browser view

struct DataBrowserView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String
    var isView: Bool = false
    var isReadOnly: Bool = false
    var columns: [ColumnInfo] = []
    @Bindable var state: DataBrowserState

    private var qualifiedName: String { "\(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName))" }
    @AppStorage("tusk.dataBrowser.pageSize") private var pageSize = 1_000
    private static let allowedPageSizes = [50, 100, 500, 1_000, 5_000]
    private var effectivePageSize: Int { Self.allowedPageSizes.contains(pageSize) ? pageSize : 1_000 }

    @State private var sortColumn: String? = nil
    @State private var sortAscending = true
    @State private var copiedInsert = false
    @State private var copiedInsertTask: Task<Void, Never>? = nil
    @State private var copiedCSV = false
    @State private var copiedCSVTask: Task<Void, Never>? = nil
    @State private var copiedJSON = false
    @State private var copiedJSONTask: Task<Void, Never>? = nil
    @State private var showingInsertSheet = false

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
                        let canInsert = !isView && !isReadOnly && columns.contains(where: { $0.isPrimaryKey })
                        ContentUnavailableView("Empty Table", systemImage: "tray",
                            description: Text(canInsert
                                ? "This table has no data. Use the + button in the toolbar to add the first row."
                                : "This table has no data."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ResultsGrid(
                            result: result,
                            columnWidthsPersistenceKey: "tusk.colwidths.\(connectionID)\u{0}\(schemaName)\u{0}\(tableName)",
                            pinnedColumnsPersistenceKey: "tusk.pinned.\(connectionID)\u{0}\(schemaName)\u{0}\(tableName)",
                            copyAsInsert: (isView || isReadOnly) ? nil : { rows in
                                copyRowsAsInsert(schema: schemaName, table: tableName, columns: result.columns, rows: rows)
                            },
                            tableColumns: (isView || isReadOnly) ? [] : columns,
                            qualifiedTableName: qualifiedName,
                            onExecuteSQL: (isView || isReadOnly) ? nil : { sql in
                                try await executeAndRefresh(sql: sql)
                            },
                            sortColumn: sortColumn,
                            sortAscending: sortAscending,
                            onSortByColumn: isView ? nil : { colName in
                                if sortColumn == colName {
                                    if sortAscending {
                                        sortAscending = false
                                    } else {
                                        sortColumn = nil
                                        sortAscending = true
                                    }
                                } else {
                                    sortColumn = colName
                                    sortAscending = true
                                }
                                triggerLoad()
                            }
                        )
                    }
                    Divider()
                    statusBar(result: result)
                }
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
        .task {
            if state.result == nil { triggerLoad() }
            if state.estimatedRowCount == nil { await loadEstimatedRowCount() }
        }
        .onChange(of: schemaName + "." + tableName) { _, _ in
            state.offset = 0
            state.filterColumn = nil
            state.estimatedRowCount = nil
            state.filteredRowCount = nil
            sortColumn = nil
            sortAscending = true
            triggerLoad()
            Task { await loadEstimatedRowCount() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if !isView && !isReadOnly && columns.contains(where: { $0.isPrimaryKey }) {
                Button {
                    showingInsertSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Insert new row")
                .sheet(isPresented: $showingInsertSheet) {
                    InsertRowSheet(
                        schemaName: schemaName,
                        tableName: tableName,
                        columns: columns,
                        onInsert: { sql in
                            try await executeAndRefresh(sql: sql)
                        }
                    )
                }
            }

            rowCountView

            Spacer()

            Picker("Column", selection: $state.filterColumn) {
                Text("All columns").tag(nil as String?)
                ForEach(columns, id: \.name) { col in
                    Text(col.name).tag(col.name as String?)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 110)
            .help("Filter on a specific column, or all columns")
            .onChange(of: state.filterColumn) { _, _ in
                guard !state.filterText.isEmpty else { return }
                state.offset = 0
                triggerLoad()
                triggerFilteredCount()
            }

            ZStack(alignment: .trailing) {
                TextField(
                    state.filterColumn == nil
                        ? "Filter rows (case-insensitive, all columns)…"
                        : "Filter \(state.filterColumn!) (case-insensitive)…",
                    text: $state.filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .help("Filters using PostgreSQL ILIKE. Use % as a wildcard (e.g. %smith%).")
                if state.isLoading && !state.filterText.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.trailing, 6)
                } else if !state.filterText.isEmpty {
                    Button {
                        state.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }
            .frame(width: 220)
            .onChange(of: state.filterText) { _, newValue in
                // Cancel any in-flight count whenever filter changes — stale results must not overwrite the new filter's count
                state.countTask?.cancel()
                state.filteredRowCount = nil
                state.isLoadingFilteredCount = false
                state.filterDebounceTask?.cancel()
                state.filterDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    state.offset = 0
                    triggerLoad()
                    if !state.filterText.isEmpty { triggerFilteredCount() }
                }
            }

            Picker("Rows", selection: $pageSize) {
                Text("50").tag(50)
                Text("100").tag(100)
                Text("500").tag(500)
                Text("1 000").tag(1_000)
                Text("5 000").tag(5_000)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 70)
            .help("Rows per page")
            .onChange(of: pageSize) { _, _ in
                state.offset = 0
                triggerLoad()
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
                    state.offset = max(0, state.offset - effectivePageSize)
                    triggerLoad()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if result.rows.count == effectivePageSize {
                Button("Next →") {
                    state.offset += effectivePageSize
                    triggerLoad()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Spacer()

            if !isView && !isReadOnly {
                Button {
                    copyRowsAsInsert(schema: schemaName, table: tableName, columns: result.columns, rows: result.rows) {
                        copiedInsert = true
                        copiedInsertTask?.cancel()
                        copiedInsertTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedInsert = false } }
                    }
                } label: {
                    Label(copiedInsert ? "Copied!" : "Copy INSERT",
                          systemImage: copiedInsert ? "checkmark" : "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy all rows as INSERT statements")
            }
            Button {
                copyRowsAsCSV(columns: result.columns, rows: result.rows) {
                    copiedCSV = true
                    copiedCSVTask?.cancel()
                    copiedCSVTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedCSV = false } }
                }
            } label: {
                Label(copiedCSV ? "Copied!" : "Copy CSV",
                      systemImage: copiedCSV ? "checkmark" : "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy all rows as CSV")
            Button {
                copyRowsAsJSON(columns: result.columns, rows: result.rows) {
                    copiedJSON = true
                    copiedJSONTask?.cancel()
                    copiedJSONTask = Task { try? await Task.sleep(for: .milliseconds(1500)); if !Task.isCancelled { copiedJSON = false } }
                }
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

    // MARK: - Row count view (#200)

    @ViewBuilder
    private var rowCountView: some View {
        if let total = state.estimatedRowCount {
            Group {
                if !state.filterText.isEmpty {
                    if state.isLoadingFilteredCount {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("of ~\(abbreviatedCount(total)) rows")
                        }
                    } else if let filtered = state.filteredRowCount {
                        Text("\(filtered.formatted()) of ~\(abbreviatedCount(total)) rows")
                    }
                } else {
                    Text("~\(abbreviatedCount(total)) rows")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func abbreviatedCount(_ n: Int64) -> String {
        switch n {
        case ..<1_000:       return n.formatted()
        case ..<1_000_000:   return String(format: "%.1fK", Double(n) / 1_000)
        default:             return String(format: "%.1fM", Double(n) / 1_000_000)
        }
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

        let baseSQL = "SELECT * FROM \(qualifiedName)"
        var orderAndPage = ""
        if let col = sortColumn {
            orderAndPage += " ORDER BY \(quoteIdentifier(col)) \(sortAscending ? "ASC" : "DESC")"
        }
        orderAndPage += " LIMIT \(effectivePageSize) OFFSET \(state.offset)"

        do {
            let queryResult: QueryResult
            if !state.filterText.isEmpty {
                // Use a parameterized query so PostgreSQL can cache the plan (#216)
                let filterValue = "%\(state.filterText)%"
                let whereClause: String
                if let col = state.filterColumn {
                    whereClause = " WHERE \(quoteIdentifier(col))::text ILIKE "
                } else {
                    whereClause = " WHERE \(quoteIdentifier(tableName))::text ILIKE "
                }
                queryResult = try await client.queryParameterized(
                    prefix: baseSQL + whereClause,
                    filterParam: filterValue,
                    suffix: orderAndPage
                )
            } else {
                queryResult = try await client.query(baseSQL + orderAndPage)
            }
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

    // MARK: - Estimated row count (#200)

    private func loadEstimatedRowCount() async {
        let escapedSchema = schemaName.replacingOccurrences(of: "'", with: "''")
        let escapedTable  = tableName.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT reltuples::bigint
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = '\(escapedSchema)' AND c.relname = '\(escapedTable)'
            """
        guard let result = try? await client.query(sql),
              let row = result.rows.first,
              case .integer(let count) = row.first else { return }
        state.estimatedRowCount = count >= 0 ? count : nil
    }

    private func triggerFilteredCount() {
        state.countTask?.cancel()
        state.isLoadingFilteredCount = true
        state.countTask = Task { await loadFilteredCount() }
    }

    private func loadFilteredCount() async {
        guard !Task.isCancelled, !state.filterText.isEmpty else {
            state.isLoadingFilteredCount = false
            return
        }
        defer { if !Task.isCancelled { state.isLoadingFilteredCount = false } }
        let filterValue = "%\(state.filterText)%"
        let wherePrefix: String
        if let col = state.filterColumn {
            wherePrefix = "SELECT COUNT(*) FROM \(qualifiedName) WHERE \(quoteIdentifier(col))::text ILIKE "
        } else {
            wherePrefix = "SELECT COUNT(*) FROM \(qualifiedName) WHERE \(quoteIdentifier(tableName))::text ILIKE "
        }
        guard let result = try? await client.queryParameterized(prefix: wherePrefix, filterParam: filterValue, suffix: ""),
              let row = result.rows.first,
              case .integer(let count) = row.first,
              !Task.isCancelled else { return }
        state.filteredRowCount = count
    }

    // MARK: - Mutating SQL

    /// Executes a mutating SQL statement (UPDATE / DELETE / INSERT) then refreshes.
    func executeAndRefresh(sql: String) async throws {
        _ = try await client.query(sql)
        triggerLoad()
    }

    // MARK: - Export

    private func exportCSV(_ result: QueryResult) {
        exportResultAsCSV(result, defaultName: tableName)
    }
}

// MARK: - Insert row sheet

private struct InsertRowSheet: View {
    let schemaName: String
    let tableName: String
    let columns: [ColumnInfo]
    let onInsert: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fieldValues: [String: String] = [:]
    @State private var nullFields: Set<String> = []
    @State private var isInserting = false
    @State private var insertError: String? = nil

    private var qualifiedName: String { "\(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName))" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Insert Row into \(tableName)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") { Task { await commitInsert() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInserting)
            }
            .padding()

            Divider()

            Form {
                ForEach(columns) { col in
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(col.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(col.dataType)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.quinary, in: Capsule())
                                if col.isPrimaryKey {
                                    Image(systemName: "key.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                if col.isNullable {
                                    Toggle("NULL", isOn: Binding(
                                        get: { nullFields.contains(col.name) },
                                        set: { if $0 { nullFields.insert(col.name) } else { nullFields.remove(col.name) } }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                                }
                            }
                            if !nullFields.contains(col.name) {
                                TextField(col.defaultValue.map { "default: \($0)" } ?? "value",
                                          text: Binding(
                                            get: { fieldValues[col.name] ?? "" },
                                            set: { fieldValues[col.name] = $0 }
                                          ))
                                .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let err = insertError {
                Divider()
                HStack {
                    Text(err).foregroundStyle(.red).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding()
            }

            if isInserting {
                Divider()
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Inserting…").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            }
        }
        .frame(width: 460)
        .frame(maxHeight: 600)
    }

    private func commitInsert() async {
        let colNames = columns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
        let values: [String] = columns.map { col in
            if nullFields.contains(col.name) { return "NULL" }
            let raw = fieldValues[col.name] ?? ""
            if raw.isEmpty { return "DEFAULT" }
            return "'\(raw.replacingOccurrences(of: "'", with: "''"))'"
        }
        let sql = "INSERT INTO \(qualifiedName) (\(colNames)) VALUES (\(values.joined(separator: ", ")))"
        isInserting = true
        insertError = nil
        do {
            try await onInsert(sql)
            dismiss()
        } catch {
            isInserting = false
            insertError = error.localizedDescription
        }
    }
}
