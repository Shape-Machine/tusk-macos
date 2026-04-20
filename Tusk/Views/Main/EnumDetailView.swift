import SwiftUI

// MARK: - Enum Detail Tab

struct EnumDetailView: View {
    let schema: String
    let enumName: String
    let client: DatabaseClient
    let connection: Connection

    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    @State private var values: [String] = []
    @State private var isLoading = true
    @State private var actionError: String? = nil

    private var isReadOnly: Bool { connection.isReadOnly }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        valuesSection
                    }
                    .padding(16)
                }
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { await reload() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet")
                .foregroundStyle(.secondary)
            Text("\(schema).\(enumName)")
                .font(.system(size: contentFontSize, weight: .semibold, design: contentFontDesign.design))
            Spacer()
            if !isReadOnly {
                Button("Add Value…") { addValue() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Rename…") { renameEnum() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Drop…") { dropEnum() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Values section

    private var valuesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Values")
                .font(.system(size: contentFontSize - 1, weight: .semibold, design: contentFontDesign.design))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                HStack(spacing: 10) {
                    Text("\(idx + 1)")
                        .font(.system(size: contentFontSize - 1, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 24, alignment: .trailing)
                    Text(value)
                        .font(.system(size: contentFontSize, design: contentFontDesign.design))
                }
                .padding(.vertical, 3)
                Divider()
            }
            if values.isEmpty {
                Text("No values")
                    .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        // Re-fetch from the live cache in AppState if available, else fall back to a direct query.
        if let cached = appState.schemaEnums[connection.id]?.first(where: { $0.schema == schema && $0.name == enumName }) {
            values = cached.values
        } else {
            if let all = try? await client.enums() {
                values = all.first(where: { $0.schema == schema && $0.name == enumName })?.values ?? []
            }
        }
        isLoading = false
    }

    private func addValue() {
        let alert = NSAlert()
        alert.messageText = "Add Value to \"\(enumName)\""
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = "new_value"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newValue = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newValue.isEmpty else { return }

        // Optional BEFORE/AFTER positioning
        let posAlert = NSAlert()
        posAlert.messageText = "Position (optional)"
        posAlert.informativeText = "Insert BEFORE an existing value, or leave blank to append at the end. (Note: PostgreSQL does not support AFTER for enum values.)"
        posAlert.addButton(withTitle: "Add")
        posAlert.addButton(withTitle: "Cancel")
        let posField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        posField.placeholderString = "existing_value (BEFORE) — leave blank to append"
        posAlert.accessoryView = posField
        posAlert.window.initialFirstResponder = posField

        guard posAlert.runModal() == .alertFirstButtonReturn else { return }
        let beforeValue = posField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let posClause = beforeValue.isEmpty ? "" : " BEFORE \(quoteLiteral(beforeValue))"
                let sql = "ALTER TYPE \(quoteIdentifier(schema)).\(quoteIdentifier(enumName)) ADD VALUE \(quoteLiteral(newValue))\(posClause);"
                _ = try await client.query(sql)
                try? await appState.refreshSchema(for: connection)
                await reload()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func renameEnum() {
        let alert = NSAlert()
        alert.messageText = "Rename Enum \"\(enumName)\""
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = enumName
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != enumName else { return }

        Task {
            do {
                _ = try await client.query("ALTER TYPE \(quoteIdentifier(schema)).\(quoteIdentifier(enumName)) RENAME TO \(quoteIdentifier(newName));")
                try? await appState.refreshSchema(for: connection)
                // Close this tab — the enum name has changed
                if let tab = appState.openTabs.first(where: {
                    if case .enumType(let cid, let s, let n) = $0.kind { return cid == connection.id && s == schema && n == enumName }
                    return false
                }) { appState.closeDetailTab(tab.id) }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func dropEnum() {
        let alert = NSAlert()
        alert.messageText = "Drop Enum \"\(enumName)\"?"
        alert.informativeText = "This permanently removes the enum type. Any columns using this type must be dropped or changed first."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Drop Enum")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                _ = try await client.query("DROP TYPE \(quoteIdentifier(schema)).\(quoteIdentifier(enumName));")
                try? await appState.refreshSchema(for: connection)
                if let tab = appState.openTabs.first(where: {
                    if case .enumType(let cid, let s, let n) = $0.kind { return cid == connection.id && s == schema && n == enumName }
                    return false
                }) { appState.closeDetailTab(tab.id) }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}
