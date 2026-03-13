import SwiftUI

struct TableDetailView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String

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
                .font(.title2)
                .fontWeight(.semibold)
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
        HStack {
            Picker("", selection: $selectedTab) {
                Text("Columns").tag(Tab.columns)
                Text("Keys").tag(Tab.keys)
                Text("Data").tag(Tab.data)
                Text("Relations").tag(Tab.relations)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            Spacer()
        }
        .background(.bar)
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
