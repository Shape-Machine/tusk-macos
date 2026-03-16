import SwiftUI

struct TableDetailView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String

    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    enum Tab { case columns, keys, relations, ddl, data }

    @State private var selectedTab: Tab = .columns
    @State private var columns: [ColumnInfo] = []
    @State private var foreignKeys: [ForeignKeyInfo] = []
    @State private var isLoadingMeta = false
    @State private var dataState = DataBrowserState()
    @State private var ddlText = ""
    @State private var isLoadingDDL = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: tableName) { await loadMeta() }
        .onChange(of: schemaName + "." + tableName) { _, _ in
            dataState.loadTask?.cancel()
            dataState.filterDebounceTask?.cancel()
            dataState.result = nil
            dataState.error = nil
            dataState.isLoading = false
            dataState.offset = 0
            dataState.filterText = ""
            ddlText = ""
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .ddl && ddlText.isEmpty && !isLoadingDDL {
                Task { await loadDDL() }
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
            DataBrowserView(client: client, connectionID: connectionID, schemaName: schemaName, tableName: tableName, state: dataState)
        case .columns:
            columnsTab
        case .keys:
            keysTab
        case .relations:
            RelationsView(client: client, schemaName: schemaName, tableName: tableName)
        case .ddl:
            DDLTab(ddlText: ddlText, isLoading: isLoadingDDL, fontSize: contentFontSize, fontDesign: contentFontDesign)
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

    // MARK: - Load metadata

    private func loadMeta() async {
        isLoadingMeta = true
        async let cols = try? await client.columns(schema: schemaName, table: tableName)
        async let fks  = try? await client.foreignKeys(schema: schemaName, table: tableName)
        columns     = await cols ?? []
        foreignKeys = await fks  ?? []
        isLoadingMeta = false
    }

    private func loadDDL() async {
        isLoadingDDL = true
        ddlText = (try? await client.tableDDL(schema: schemaName, table: tableName)) ?? ""
        isLoadingDDL = false
    }
}

// MARK: - DDL tab

private struct DDLTab: View {
    let ddlText: String
    let isLoading: Bool
    let fontSize: Double
    let fontDesign: TuskFontDesign

    var body: some View {
        if isLoading {
            ProgressView("Loading…")
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
