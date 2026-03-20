import SwiftUI

struct TableDetailView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String
    var isView: Bool = false

    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    enum Tab { case columns, keys, relations, indexes, triggers, ddl, data }

    @State private var selectedTab: Tab = .columns
    @State private var columns: [ColumnInfo] = []
    @State private var foreignKeys: [ForeignKeyInfo] = []
    @State private var isLoadingMeta = false
    @State private var dataState = DataBrowserState()
    @State private var indexes: [IndexInfo] = []
    @State private var indexesError: String? = nil
    @State private var isLoadingIndexes = false
    @State private var indexesLoadTask: Task<Void, Never>? = nil
    @State private var triggers: [TriggerInfo] = []
    @State private var triggersError: String? = nil
    @State private var isLoadingTriggers = false
    @State private var triggersLoadTask: Task<Void, Never>? = nil
    @State private var ddlText = ""
    @State private var ddlError: String? = nil
    @State private var isLoadingDDL = false
    @State private var ddlLoadTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: schemaName + "." + tableName) { await loadMeta() }
        .onChange(of: schemaName + "." + tableName) { _, _ in
            columns = []
            foreignKeys = []
            dataState.loadTask?.cancel()
            dataState.filterDebounceTask?.cancel()
            dataState.result = nil
            dataState.error = nil
            dataState.isLoading = false
            dataState.offset = 0
            dataState.filterText = ""
            indexesLoadTask?.cancel()
            indexesLoadTask = nil
            indexes = []
            indexesError = nil
            isLoadingIndexes = false
            triggersLoadTask?.cancel()
            triggersLoadTask = nil
            triggers = []
            triggersError = nil
            isLoadingTriggers = false
            ddlLoadTask?.cancel()
            ddlLoadTask = nil
            ddlText = ""
            ddlError = nil
            isLoadingDDL = false
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .indexes && indexes.isEmpty && !isLoadingIndexes {
                indexesLoadTask = Task { await loadIndexes() }
            }
            if newTab == .triggers && triggers.isEmpty && !isLoadingTriggers {
                triggersLoadTask = Task { await loadTriggers() }
            }
            if newTab == .ddl && ddlText.isEmpty && !isLoadingDDL {
                ddlLoadTask = Task { await loadDDL() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .foregroundStyle(.blue)
            Text(tableName)
                .font(.system(size: contentFontSize + 8, weight: .semibold, design: contentFontDesign.design))
            Text(schemaName)
                .font(.system(.caption, design: contentFontDesign.design))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 2) {
            tabSegment("Columns", for: .columns)
            tabSegment("Keys", for: .keys)
            tabSegment("Relations", for: .relations)
            tabSegment("Indexes", for: .indexes)
            tabSegment("Triggers", for: .triggers)
            tabSegment("DDL", for: .ddl)
            tabSegment("Data", for: .data)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private func tabSegment(_ title: String, for tab: Tab) -> some View {
        Button { selectedTab = tab } label: {
            Text(title)
                .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    selectedTab == tab ? Color(nsColor: .selectedControlColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .data:
            DataBrowserView(client: client, connectionID: connectionID, schemaName: schemaName, tableName: tableName, isView: isView, state: dataState)
        case .columns:
            columnsTab
        case .keys:
            keysTab
        case .relations:
            RelationsView(client: client, schemaName: schemaName, tableName: tableName)
        case .indexes:
            indexesTab
        case .triggers:
            triggersTab
        case .ddl:
            DDLTab(ddlText: ddlText, ddlError: ddlError, isLoading: isLoadingDDL, fontSize: contentFontSize, fontDesign: contentFontDesign)
        }
    }

    // MARK: - Columns tab

    private var columnsTab: some View {
        Group {
            if isLoadingMeta {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(columns) {
                    TableColumn("Column") { col in
                        HStack(spacing: 4) {
                            if col.isPrimaryKey {
                                Image(systemName: "key.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(col.name)
                        }
                    }
                    TableColumn("Type") { col in
                        Text(col.dataType).foregroundStyle(.secondary)
                    }
                    TableColumn("Nullable") { col in
                        Text(col.isNullable ? "YES" : "NO")
                            .foregroundStyle(col.isNullable ? .secondary : .primary)
                    }
                    TableColumn("Default") { col in
                        Text(col.defaultValue ?? "—").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keys tab

    private var keysTab: some View {
        Group {
            if isLoadingMeta {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if foreignKeys.isEmpty {
                ContentUnavailableView("No foreign keys", systemImage: "link")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(foreignKeys) {
                    TableColumn("Constraint", value: \.constraintName)
                    TableColumn("Column", value: \.fromColumn)
                    TableColumn("References") { fk in
                        Text("\(fk.toTable)(\(fk.toColumn))")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Indexes tab

    private var indexesTab: some View {
        Group {
            if isLoadingIndexes {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = indexesError {
                ContentUnavailableView("Failed to load indexes", systemImage: "exclamationmark.triangle")
                    .help(error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if indexes.isEmpty {
                ContentUnavailableView("No indexes", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(indexes) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Unique") { idx in
                        Text(idx.isUnique ? "YES" : "NO")
                            .foregroundStyle(idx.isUnique ? .primary : .secondary)
                    }
                    TableColumn("Primary") { idx in
                        Text(idx.isPrimary ? "YES" : "NO")
                            .foregroundStyle(idx.isPrimary ? .primary : .secondary)
                    }
                    TableColumn("Definition", value: \.definition)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Triggers tab

    private var triggersTab: some View {
        Group {
            if isLoadingTriggers {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = triggersError {
                ContentUnavailableView("Failed to load triggers", systemImage: "exclamationmark.triangle")
                    .help(error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if triggers.isEmpty {
                ContentUnavailableView("No triggers", systemImage: "bolt.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(triggers) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Timing", value: \.timing)
                    TableColumn("Event", value: \.event)
                    TableColumn("Statement", value: \.statement)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load metadata

    private func loadMeta() async {
        isLoadingMeta = true
        async let cols = try? await client.columns(schema: schemaName, table: tableName)
        async let fks  = try? await client.foreignKeys(schema: schemaName, table: tableName)
        columns     = await cols ?? []
        foreignKeys = await fks  ?? []
        isLoadingMeta = false
    }

    private func loadIndexes() async {
        isLoadingIndexes = true
        do {
            let result = try await client.fetchIndexes(schema: schemaName, table: tableName)
            guard !Task.isCancelled else { isLoadingIndexes = false; return }
            indexes = result
            indexesError = nil
        } catch {
            guard !Task.isCancelled else { isLoadingIndexes = false; return }
            indexesError = error.localizedDescription
        }
        isLoadingIndexes = false
    }

    private func loadTriggers() async {
        isLoadingTriggers = true
        do {
            let result = try await client.fetchTriggers(schema: schemaName, table: tableName)
            guard !Task.isCancelled else { isLoadingTriggers = false; return }
            triggers = result
            triggersError = nil
        } catch {
            guard !Task.isCancelled else { isLoadingTriggers = false; return }
            triggersError = error.localizedDescription
        }
        isLoadingTriggers = false
    }

    private func loadDDL() async {
        isLoadingDDL = true
        do {
            let result = try await client.tableDDL(schema: schemaName, table: tableName)
            guard !Task.isCancelled else { isLoadingDDL = false; return }
            ddlText = result
            ddlError = nil
        } catch {
            guard !Task.isCancelled else { isLoadingDDL = false; return }
            ddlError = error.localizedDescription
        }
        isLoadingDDL = false
    }
}

// MARK: - DDL tab

private struct DDLTab: View {
    let ddlText: String
    let ddlError: String?
    let isLoading: Bool
    let fontSize: Double
    let fontDesign: TuskFontDesign

    var body: some View {
        if isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = ddlError {
            ContentUnavailableView("Failed to load DDL", systemImage: "exclamationmark.triangle")
                .help(error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if ddlText.isEmpty {
            ContentUnavailableView("No DDL available", systemImage: "doc.text")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ddlText, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
                SQLTextEditor(text: .constant(ddlText), fontSize: fontSize, isEditable: false)
            }
        }
    }
}
