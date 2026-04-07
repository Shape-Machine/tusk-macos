import SwiftUI

// MARK: - Add Constraint sheet

struct AddConstraintSheet: View {
    let schemaName: String
    let tableName: String
    let tableColumns: [ColumnInfo]
    let client: DatabaseClient
    let onAdded: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var constraintType: ConstraintType = .unique
    @State private var constraintName: String = ""
    @State private var selectedColumns: Set<String> = []
    @State private var checkExpression: String = ""
    @State private var refSchema: String = "public"
    @State private var refTable: String = ""
    @State private var refColumn: String = ""
    @State private var refTables: [String] = []
    @State private var refColumns: [String] = []
    @State private var isLoadingRefTables: Bool = false
    @State private var isAdding: Bool = false
    @State private var addError: String? = nil

    enum ConstraintType: String, CaseIterable, Identifiable {
        case primaryKey = "PRIMARY KEY"
        case unique     = "UNIQUE"
        case foreignKey = "FOREIGN KEY"
        case check      = "CHECK"
        var id: String { rawValue }
    }

    private var qualifiedTable: String {
        "\(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName))"
    }

    private var generatedSQL: String {
        let nameClause = constraintName.trimmingCharacters(in: .whitespacesAndNewlines)
        let constraintClause = nameClause.isEmpty ? "ADD" : "ADD CONSTRAINT \(quoteIdentifier(nameClause))"
        let colList = selectedColumns.sorted().map { quoteIdentifier($0) }.joined(separator: ", ")

        switch constraintType {
        case .primaryKey:
            guard !selectedColumns.isEmpty else { return "-- Select at least one column" }
            return "ALTER TABLE \(qualifiedTable) \(constraintClause) PRIMARY KEY (\(colList));"
        case .unique:
            guard !selectedColumns.isEmpty else { return "-- Select at least one column" }
            return "ALTER TABLE \(qualifiedTable) \(constraintClause) UNIQUE (\(colList));"
        case .foreignKey:
            guard !selectedColumns.isEmpty, !refTable.isEmpty, !refColumn.isEmpty else {
                return "-- Select source column(s), reference table and reference column"
            }
            let refQ = "\(quoteIdentifier(refSchema)).\(quoteIdentifier(refTable))"
            return "ALTER TABLE \(qualifiedTable) \(constraintClause) FOREIGN KEY (\(colList)) REFERENCES \(refQ) (\(quoteIdentifier(refColumn)));"
        case .check:
            let expr = checkExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expr.isEmpty else { return "-- Enter a CHECK expression" }
            return "ALTER TABLE \(qualifiedTable) \(constraintClause) CHECK (\(expr));"
        }
    }

    private var canAdd: Bool {
        switch constraintType {
        case .primaryKey, .unique:   return !selectedColumns.isEmpty
        case .foreignKey:            return !selectedColumns.isEmpty && !refTable.isEmpty && !refColumn.isEmpty
        case .check:                 return !checkExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Constraint to \"\(tableName)\"")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isAdding ? "Adding…" : "Add") { Task { await commitAdd() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd || isAdding)
            }
            .padding()

            Divider()

            Form {
                Section("Constraint") {
                    Picker("Type", selection: $constraintType) {
                        ForEach(ConstraintType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .onChange(of: constraintType) { _, _ in
                        selectedColumns = []
                        addError = nil
                        if constraintType == .foreignKey && refTables.isEmpty {
                            Task { await loadRefTables() }
                        }
                    }

                    TextField("Constraint name (optional)", text: $constraintName)
                }

                if constraintType == .primaryKey || constraintType == .unique || constraintType == .foreignKey {
                    Section(constraintType == .foreignKey ? "Source Columns" : "Columns") {
                        if tableColumns.isEmpty {
                            Text("No columns available").foregroundStyle(.secondary)
                        } else {
                            ForEach(tableColumns) { col in
                                Toggle(col.name, isOn: Binding(
                                    get: { selectedColumns.contains(col.name) },
                                    set: { if $0 { selectedColumns.insert(col.name) } else { selectedColumns.remove(col.name) } }
                                ))
                            }
                        }
                    }
                }

                if constraintType == .foreignKey {
                    Section("Reference") {
                        if isLoadingRefTables {
                            HStack { ProgressView().controlSize(.small); Text("Loading tables…").foregroundStyle(.secondary) }
                        } else {
                            if refTables.isEmpty {
                                TextField("Reference table", text: $refTable)
                                    .onSubmit { Task { await loadRefColumns() } }
                            } else {
                                Picker("Table", selection: $refTable) {
                                    Text("—").tag("")
                                    ForEach(refTables, id: \.self) { t in Text(t).tag(t) }
                                }
                                .onChange(of: refTable) { _, _ in
                                    refColumn = ""
                                    refColumns = []
                                    if !refTable.isEmpty { Task { await loadRefColumns() } }
                                }
                            }
                            if !refTable.isEmpty {
                                if refColumns.isEmpty {
                                    TextField("Reference column", text: $refColumn)
                                } else {
                                    Picker("Column", selection: $refColumn) {
                                        Text("—").tag("")
                                        ForEach(refColumns, id: \.self) { c in Text(c).tag(c) }
                                    }
                                }
                            }
                        }
                    }
                }

                if constraintType == .check {
                    Section("Expression") {
                        TextField("e.g. age > 0", text: $checkExpression)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .formStyle(.grouped)

            if let err = addError {
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
                    .foregroundStyle(canAdd ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.bar)
        }
        .frame(width: 480)
        .frame(maxHeight: 640)
        .task {
            if constraintType == .foreignKey { await loadRefTables() }
        }
    }

    // MARK: - Load reference tables

    private func loadRefTables() async {
        isLoadingRefTables = true
        let s = schemaName.replacingOccurrences(of: "'", with: "''")
        let result = try? await client.query("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = '\(s)' AND table_type = 'BASE TABLE'
            ORDER BY table_name
            """)
        refTables = result?.rows.compactMap { $0.first?.displayValue } ?? []
        isLoadingRefTables = false
    }

    private func loadRefColumns() async {
        guard !refTable.isEmpty else { return }
        let s = schemaName.replacingOccurrences(of: "'", with: "''")
        let t = refTable.replacingOccurrences(of: "'", with: "''")
        let result = try? await client.query("""
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = '\(s)' AND table_name = '\(t)'
            ORDER BY ordinal_position
            """)
        refColumns = result?.rows.compactMap { $0.first?.displayValue } ?? []
    }

    // MARK: - Commit

    private func commitAdd() async {
        guard canAdd else { return }
        isAdding = true
        addError = nil
        do {
            _ = try await client.query(generatedSQL)
            await onAdded()
            dismiss()
        } catch {
            isAdding = false
            addError = error.localizedDescription
        }
    }
}
