import SwiftUI

// MARK: - Create table target (stable identity for sheet presentation)

struct CreateTableTarget: Identifiable {
    let id = UUID()
    let schema: String
    let connectionID: UUID
}

// MARK: - Column type list

let pgColumnTypes: [String] = [
    "text", "varchar", "char",
    "integer", "bigint", "smallint", "numeric", "real", "double precision",
    "boolean",
    "date", "timestamp", "timestamptz",
    "uuid",
    "json", "jsonb",
    "bytea"
]

// MARK: - Column definition model

struct ColumnDef: Identifiable {
    let id = UUID()
    var name: String = ""
    var type: String = "text"
    var nullable: Bool = true
    var defaultValue: String = ""
    var isPrimaryKey: Bool = false
}

// MARK: - Create Table sheet

struct CreateTableSheet: View {
    let schemaName: String
    let client: DatabaseClient
    let onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tableName = ""
    @State private var columns: [ColumnDef] = [ColumnDef()]
    @State private var isCreating = false
    @State private var createError: String? = nil

    private var canCreate: Bool {
        !tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        columns.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var ddlPreview: String {
        let tName = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tName.isEmpty else { return "-- Enter a table name to preview DDL" }
        let validCols = columns.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validCols.isEmpty else { return "-- Add at least one column to preview DDL" }

        let t = "\(quoteIdentifier(schemaName)).\(quoteIdentifier(tName))"
        var defs = validCols.map { col -> String in
            let colName = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var def = "  \(quoteIdentifier(colName)) \(col.type)"
            if !col.defaultValue.isEmpty { def += " DEFAULT \(col.defaultValue)" }
            if !col.nullable { def += " NOT NULL" }
            return def
        }
        let pkCols = validCols.filter { $0.isPrimaryKey }
        if !pkCols.isEmpty {
            let pkList = pkCols.map { quoteIdentifier($0.name.trimmingCharacters(in: .whitespacesAndNewlines)) }.joined(separator: ", ")
            defs.append("  PRIMARY KEY (\(pkList))")
        }
        return "CREATE TABLE \(t) (\n\(defs.joined(separator: ",\n"))\n);"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tableNameRow
            Divider()
            columnsHeader
            columnListHeader
            columnList
            if let err = createError {
                errorBanner(err)
            }
            Divider()
            ddlPreviewSection
        }
        .frame(minWidth: 700, idealWidth: 740, minHeight: 460, idealHeight: 540)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Create Table in \"\(schemaName)\"")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isCreating ? "Creating…" : "Create") { createTable() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || isCreating)
        }
        .padding()
    }

    // MARK: - Table name row

    private var tableNameRow: some View {
        HStack(spacing: 8) {
            Text("Table name")
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            TextField("new_table", text: $tableName)
                .onChange(of: tableName) { _, _ in createError = nil }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Columns section header

    private var columnsHeader: some View {
        HStack {
            Text("Columns")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Button {
                columns.append(ColumnDef())
            } label: {
                Label("Add Column", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Column list column headers

    private var columnListHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Name")
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                Text("Type")
                    .frame(width: 150, alignment: .leading)
                Text("PK")
                    .frame(width: 30, alignment: .center)
                Text("Nullable")
                    .frame(width: 65, alignment: .center)
                Text("Default")
                    .frame(width: 110, alignment: .leading)
                Spacer().frame(width: 24)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.quinary)
            Divider()
        }
    }

    // MARK: - Column list

    private var columnList: some View {
        List {
            ForEach(columns.indices, id: \.self) { idx in
                ColumnRow(col: $columns[idx]) {
                    columns.remove(at: idx)
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - DDL preview

    private var ddlPreviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DDL Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ScrollView {
                Text(ddlPreview)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            .frame(height: 90)
        }
        .background(.bar)
    }

    // MARK: - Create table

    private func createTable() {
        let tName = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        let validCols = columns.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !tName.isEmpty, !validCols.isEmpty else { return }

        let dangerous = [";", "--", "/*", "*/"]
        for col in validCols {
            for value in [col.type, col.defaultValue] where !value.isEmpty {
                if dangerous.contains(where: { value.contains($0) }) {
                    createError = "Column type and default must not contain SQL metacharacters (; -- /* */)."
                    return
                }
            }
        }

        isCreating = true
        createError = nil
        Task {
            do {
                _ = try await client.query(ddlPreview)
                await onCreated()
                dismiss()
            } catch {
                createError = error.localizedDescription
                isCreating = false
            }
        }
    }
}

// MARK: - Column row

private struct ColumnRow: View {
    @Binding var col: ColumnDef
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("name", text: $col.name)
                .frame(minWidth: 100, maxWidth: .infinity)
            Picker("", selection: $col.type) {
                ForEach(pgColumnTypes, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .frame(width: 150)
            Toggle("", isOn: $col.isPrimaryKey)
                .toggleStyle(.checkbox)
                .frame(width: 30, alignment: .center)
                .onChange(of: col.isPrimaryKey) { _, pk in
                    if pk { col.nullable = false }
                }
            Toggle("", isOn: $col.nullable)
                .toggleStyle(.checkbox)
                .frame(width: 65, alignment: .center)
                .disabled(col.isPrimaryKey)
            TextField("default", text: $col.defaultValue)
                .frame(width: 110)
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .frame(width: 24)
        }
    }
}
