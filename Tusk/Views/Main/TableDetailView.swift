import SwiftUI

struct TableDetailView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String

    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0

    enum Tab { case columns, keys, data, relations }

    @State private var selectedTab: Tab = .columns
    @State private var columns: [ColumnInfo] = []
    @State private var foreignKeys: [ForeignKeyInfo] = []
    @State private var isLoadingMeta = false

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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .foregroundStyle(.blue)
            Text(tableName)
                .font(.system(size: contentFontSize + 8, weight: .semibold))
            Text(schemaName)
                .font(.caption)
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
                .font(.system(size: contentFontSize - 1))
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
            DataBrowserView(client: client, connectionID: connectionID, schemaName: schemaName, tableName: tableName)
        case .columns:
            columnsTab
        case .keys:
            keysTab
        case .relations:
            RelationsView(client: client, schemaName: schemaName, tableName: tableName)
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
}
