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

    @State private var sshEnabled: Bool = false
    @State private var sshHost: String = ""
    @State private var sshPort: String = "22"
    @State private var sshUser: String = ""
    @State private var sshKeyPath: String = ""
    @State private var sshPassphrase: String = ""

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
                                    Label {
                                        Text(c.rawValue.capitalized)
                                    } icon: {
                                        Image(systemName: color == c ? "checkmark.circle.fill" : "circle.fill")
                                            .foregroundStyle(c.color)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("●")
                                    .foregroundColor(color.color)
                                    .font(.system(size: 11))
                                Text(color.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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

                Section {
                    Toggle("Use SSH Tunnel", isOn: $sshEnabled)

                    if sshEnabled {
                        HStack {
                            TextField("SSH Host", text: $sshHost)
                            TextField("SSH Port", text: $sshPort)
                                .labelsHidden()
                                .frame(width: 80)
                        }
                        TextField("SSH User", text: $sshUser)
                        HStack {
                            TextField("Private Key Path", text: $sshKeyPath)
                            Button("Browse…") { pickKey() }
                                .buttonStyle(.borderless)
                        }
                        SecureField("Key Passphrase (if any)", text: $sshPassphrase)
                    }
                } header: {
                    Text("SSH Tunnel")
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
        name          = c.name
        host          = c.host
        port          = String(c.port)
        database      = c.database
        username      = c.username
        password      = KeychainManager.shared.password(for: c.id) ?? ""
        useSSL        = c.useSSL
        color         = c.color
        sshEnabled    = c.sshEnabled
        sshHost       = c.sshHost
        sshPort       = String(c.sshPort)
        sshUser       = c.sshUser
        sshKeyPath    = c.sshKeyPath
        sshPassphrase = KeychainManager.shared.sshPassphrase(for: c.id) ?? ""
    }

    private func pickKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Key"
        panel.title = "Choose SSH Private Key"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPath = url.path
        }
    }

    private func save() {
        let portInt    = Int(port) ?? 5432
        let sshPortInt = Int(sshPort) ?? 22
        if let existing = connection {
            var updated          = existing
            updated.name         = name
            updated.host         = host
            updated.port         = portInt
            updated.database     = database
            updated.username     = username
            updated.useSSL       = useSSL
            updated.color        = color
            updated.sshEnabled   = sshEnabled
            updated.sshHost      = sshHost
            updated.sshPort      = sshPortInt
            updated.sshUser      = sshUser
            updated.sshKeyPath   = sshKeyPath
            KeychainManager.shared.setPassword(password, for: updated.id)
            KeychainManager.shared.setSshPassphrase(sshPassphrase, for: updated.id)
            appState.updateConnection(updated)
        } else {
            var new          = Connection(
                name: name, host: host, port: portInt,
                database: database, username: username,
                useSSL: useSSL, color: color
            )
            new.sshEnabled   = sshEnabled
            new.sshHost      = sshHost
            new.sshPort      = sshPortInt
            new.sshUser      = sshUser
            new.sshKeyPath   = sshKeyPath
            KeychainManager.shared.setPassword(password, for: new.id)
            KeychainManager.shared.setSshPassphrase(sshPassphrase, for: new.id)
            appState.addConnection(new)
        }
        dismiss()
    }

    private func testConnection() async {
        isTestingConnection = true
        testResult = nil

        var info        = Connection(
            name: name, host: host, port: Int(port) ?? 5432,
            database: database, username: username, useSSL: useSSL
        )
        info.sshEnabled = sshEnabled
        info.sshHost    = sshHost
        info.sshPort    = Int(sshPort) ?? 22
        info.sshUser    = sshUser
        info.sshKeyPath = sshKeyPath

        var tunnel: SSHTunnel? = nil

        do {
            // Start SSH tunnel if enabled and patch host/port to the local end.
            if sshEnabled {
                let t = SSHTunnel()
                try await t.start(
                    connection: info,
                    passphrase: sshPassphrase.isEmpty ? nil : sshPassphrase
                )
                tunnel    = t
                info.host = "127.0.0.1"
                info.port = await t.localPort
            }

            let client = DatabaseClient()
            do {
                try await client.connect(to: info, password: password)
                await client.disconnect()
                testResult = "✓ Connected successfully"
            } catch {
                testResult = "✗ \(friendlyError(error))"
            }
        } catch {
            testResult = "✗ \(friendlyError(error))"
        }

        if let tunnel { await tunnel.stop() }
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
