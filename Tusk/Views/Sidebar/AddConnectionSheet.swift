import SwiftUI
import PostgresNIO

struct AddConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // nil = new connection, non-nil = editing existing
    let connection: Connection?

    @State private var name: String = ""
    @State private var host: String = "localhost"
    @State private var port: String = "5432"
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var useSSL: Bool = false
    @State private var color: ConnectionColor = .blue

    @State private var isTestingConnection = false
    @State private var testResult: String? = nil

    var isEditing: Bool { connection != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Connection" : "New Connection")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || host.isEmpty || database.isEmpty || username.isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Connection") {
                    HStack(spacing: 8) {
                        TextField("Name", text: $name)
                        Menu {
                            ForEach(ConnectionColor.allCases, id: \.self) { c in
                                Button {
                                    color = c
                                } label: {
                                    Label(c.rawValue.capitalized, systemImage: color == c ? "checkmark.circle.fill" : "circle.fill")
                                        .foregroundStyle(c.color)
                                }
                            }
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 18, height: 18)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Connection color")
                    }
                }

                Section("Host") {
                    HStack {
                        TextField("Host", text: $host)
                        TextField("Port", text: $port)
                            .frame(width: 70)
                    }
                    TextField("Database", text: $database)
                }

                Section("Authentication") {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    Toggle("Use SSL", isOn: $useSSL)
                }

                if let result = testResult {
                    Section {
                        Text(result)
                            .foregroundStyle(result.hasPrefix("✓") ? Color.green : Color.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer with test button
            HStack {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTestingConnection {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(host.isEmpty || database.isEmpty || username.isEmpty)

                Spacer()
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear { populate() }
    }

    // MARK: - Actions

    private func populate() {
        guard let c = connection else { return }
        name     = c.name
        host     = c.host
        port     = String(c.port)
        database = c.database
        username = c.username
        password = KeychainManager.shared.password(for: c.id) ?? ""
        useSSL   = c.useSSL
        color    = c.color
    }

    private func save() {
        let portInt = Int(port) ?? 5432
        if let existing = connection {
            var updated = existing
            updated.name     = name
            updated.host     = host
            updated.port     = portInt
            updated.database = database
            updated.username = username
            updated.useSSL   = useSSL
            updated.color    = color
            KeychainManager.shared.setPassword(password, for: updated.id)
            appState.updateConnection(updated)
        } else {
            let new = Connection(
                name: name, host: host, port: portInt,
                database: database, username: username,
                useSSL: useSSL, color: color
            )
            KeychainManager.shared.setPassword(password, for: new.id)
            appState.addConnection(new)
        }
        dismiss()
    }

    private func testConnection() async {
        isTestingConnection = true
        testResult = nil

        let info = Connection(
            name: name, host: host, port: Int(port) ?? 5432,
            database: database, username: username, useSSL: useSSL
        )

        let client = DatabaseClient()
        do {
            try await client.connect(to: info, password: password)
            await client.disconnect()
            testResult = "✓ Connected successfully"
        } catch {
            testResult = "✗ \(friendlyError(error))"
        }

        isTestingConnection = false
    }
}

// MARK: - Readable error messages for PSQLError

private func friendlyError(_ error: any Error) -> String {
    if let psql = error as? PSQLError {
        // Server sent a message (auth failure, db not found, etc.)
        if let msg = psql.serverInfo?[.message] {
            if let detail = psql.serverInfo?[.detail] {
                return "\(msg) — \(detail)"
            }
            return msg
        }
        // No server message — use the code description
        switch psql.code {
        case .sslUnsupported:
            return "SSL is not enabled on this server. Turn off Use SSL and try again."
        case .connectionError:
            return "Could not reach the server. Check the host and port."
        case .authMechanismRequiresPassword:
            return "A password is required."
        case .unsupportedAuthMechanism:
            return "The server uses an unsupported authentication method."
        default:
            return "Connection failed (\(psql.code))."
        }
    }
    return error.localizedDescription
}
