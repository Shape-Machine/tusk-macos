import SwiftUI

// MARK: - Create Role / User sheet

struct CreateRoleSheet: View {
    let client: DatabaseClient
    let connection: Connection
    let onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var roleName = ""
    @State private var isLogin = false
    @State private var password = ""
    @State private var isSuperuser = false
    @State private var createDB = false
    @State private var createRole = false
    @State private var inherit = true
    @State private var replication = false
    @State private var connLimit = ""          // empty = no limit
    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var isCreating = false
    @State private var createError: String? = nil

    private var trimmedName: String { roleName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !trimmedName.isEmpty }

    private var generatedSQL: String {
        guard canCreate else { return "-- Enter a role name" }
        var parts: [String] = []
        parts.append(isLogin   ? "LOGIN"       : "NOLOGIN")
        parts.append(isSuperuser ? "SUPERUSER" : "NOSUPERUSER")
        parts.append(inherit   ? "INHERIT"     : "NOINHERIT")
        parts.append(createDB  ? "CREATEDB"    : "NOCREATEDB")
        parts.append(createRole ? "CREATEROLE" : "NOCREATEROLE")
        parts.append(replication ? "REPLICATION" : "NOREPLICATION")
        if let limit = Int(connLimit.trimmingCharacters(in: .whitespaces)) {
            parts.append("CONNECTION LIMIT \(limit)")
        }
        if hasExpiry {
            let fmt = ISO8601DateFormatter()
            parts.append("VALID UNTIL '\(fmt.string(from: expiryDate))'")
        }
        // Password is intentionally omitted from the SQL preview
        let attrClause = parts.joined(separator: " ")
        let cmd = isLogin ? "CREATE USER" : "CREATE ROLE"
        return "\(cmd) \(quoteIdentifier(trimmedName)) \(attrClause);"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create \(isLogin ? "User" : "Role")")
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
                Section("Identity") {
                    TextField("Role name", text: $roleName)
                    Toggle("Can login (User)", isOn: $isLogin)
                    if isLogin {
                        SecureField("Password (optional)", text: $password)
                    }
                }

                Section("Privileges") {
                    Toggle("Superuser",   isOn: $isSuperuser)
                    Toggle("Create DB",   isOn: $createDB)
                    Toggle("Create role", isOn: $createRole)
                    Toggle("Inherit",     isOn: $inherit)
                    Toggle("Replication", isOn: $replication)
                }

                Section("Limits") {
                    HStack {
                        Text("Connection limit")
                        Spacer()
                        TextField("∞", text: $connLimit)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .font(.system(.body, design: .monospaced))
                    }
                    Toggle("Expires", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expiry date", selection: $expiryDate, displayedComponents: .date)
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

            // SQL preview (password never shown)
            VStack(alignment: .leading, spacing: 4) {
                Text("SQL Preview")
                    .font(.caption).foregroundStyle(.secondary)
                Text(generatedSQL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(canCreate ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isLogin && !password.isEmpty {
                    Text("+ ALTER ROLE … PASSWORD '••••••••';")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.bar)
        }
        .frame(width: 460)
        .frame(maxHeight: 600)
    }

    private func commitCreate() async {
        guard canCreate else { return }
        isCreating = true
        createError = nil
        do {
            _ = try await client.query(generatedSQL)
            if isLogin && !password.isEmpty {
                let escaped = password.replacingOccurrences(of: "'", with: "''")
                _ = try await client.query("ALTER ROLE \(quoteIdentifier(trimmedName)) PASSWORD '\(escaped)';")
            }
            await onCreated()
            dismiss()
        } catch {
            isCreating = false
            createError = error.localizedDescription
        }
    }
}
