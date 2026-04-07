import SwiftUI

// MARK: - Create Index sheet

struct CreateIndexSheet: View {
    let schemaName: String
    let tableName: String
    let tableColumns: [ColumnInfo]
    let client: DatabaseClient
    let onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var indexName: String = ""
    @State private var selectedColumns: [String] = []
    @State private var method: IndexMethod = .btree
    @State private var isUnique: Bool = false
    @State private var isConcurrently: Bool = false
    @State private var isCreating: Bool = false
    @State private var createError: String? = nil

    enum IndexMethod: String, CaseIterable, Identifiable {
        case btree, hash, gin, gist, brin
        var id: String { rawValue }
        var displayName: String { rawValue.uppercased() }
    }

    private var qualifiedTable: String {
        "\(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName))"
    }

    private var orderedColumns: [String] { selectedColumns }

    private var generatedSQL: String {
        guard !indexName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedColumns.isEmpty else {
            return "-- Enter an index name and select at least one column"
        }
        let name = indexName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cols = orderedColumns.map { quoteIdentifier($0) }.joined(separator: ", ")
        var sql = "CREATE"
        if isUnique { sql += " UNIQUE" }
        sql += " INDEX"
        if isConcurrently { sql += " CONCURRENTLY" }
        sql += " \(quoteIdentifier(name))"
        sql += " ON \(qualifiedTable)"
        sql += " USING \(method.rawValue)"
        sql += " (\(cols));"
        return sql
    }

    private var canCreate: Bool {
        !indexName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedColumns.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Index on \"\(tableName)\"")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isCreating ? "Creating…" : "Create") { Task { await commitCreate() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || isCreating)
            }
            .padding()

            Divider()

            Form {
                Section("Index") {
                    HStack {
                        Text("Name")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        TextField("index_name", text: $indexName)
                    }
                    HStack {
                        Text("Method")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Picker("", selection: $method) {
                            ForEach(IndexMethod.allCases) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    HStack {
                        Text("")
                            .frame(width: 80, alignment: .trailing)
                        Toggle("Unique", isOn: $isUnique)
                    }
                    HStack {
                        Text("")
                            .frame(width: 80, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Build concurrently", isOn: $isConcurrently)
                            if isConcurrently {
                                Text("CONCURRENTLY cannot run inside a transaction and may take longer to complete.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Columns") {
                    if tableColumns.isEmpty {
                        Text("No columns available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tableColumns) { col in
                            Toggle(col.name, isOn: Binding(
                                get: { selectedColumns.contains(col.name) },
                                set: { checked in
                                    if checked {
                                        selectedColumns.append(col.name)
                                    } else {
                                        selectedColumns.removeAll { $0 == col.name }
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let err = createError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding()
            }

            Divider()

            // SQL preview
            VStack(alignment: .leading, spacing: 4) {
                Text("SQL Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(generatedSQL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(canCreate ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.bar)
        }
        .frame(width: 480)
        .frame(maxHeight: 600)
    }

    private func commitCreate() async {
        guard canCreate else { return }
        isCreating = true
        createError = nil
        do {
            _ = try await client.query(generatedSQL)
            await onCreated()
            dismiss()
        } catch {
            isCreating = false
            createError = error.localizedDescription
        }
    }
}
