import SwiftUI
import PostgresNIO

struct AddConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // nil = new connection, non-nil = editing existing
    let connection: Connection?

    @State private var connectionType: ConnectionType = .direct

    // Direct TCP fields
    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var host: String = "localhost"
    @State private var port: String = "5432"
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var useSSL: Bool = false
    @State private var verifySSLCertificate: Bool = false
    @State private var isReadOnly: Bool = false
    @State private var color: ConnectionColor = .blue

    @State private var sshEnabled: Bool = false
    @State private var sshHost: String = ""
    @State private var sshPort: String = "22"
    @State private var sshUser: String = ""
    @State private var sshKeyPath: String = ""
    @State private var sshPassphrase: String = ""

    // Cloud SQL fields
    @State private var cloudSQLInstanceConnectionName: String = ""
    @State private var cloudSQLProject: String = ""
    @State private var useADC: Bool = false
    @State private var showingInstancePicker = false
    @State private var availableDatabases: [String] = []
    @State private var isLoadingDatabases = false
    @State private var showingDatabasePopover = false

    @State private var isTestingConnection = false
    @State private var testResult: String? = nil
    @State private var uriError: String? = nil
    @State private var testProxy: CloudSQLProxy? = nil
    @State private var gcloudAvailable: Bool = true

    var isEditing: Bool { connection != nil }

    private var isCloudSQL: Bool { connectionType == .cloudSQL }

    private var saveDisabled: Bool {
        if isCloudSQL {
            return name.isEmpty || cloudSQLInstanceConnectionName.isEmpty || database.isEmpty || username.isEmpty
        }
        return name.isEmpty || host.isEmpty || database.isEmpty || username.isEmpty
    }

    /// A string that changes whenever any field that affects connectivity changes.
    /// Used to clear the stale test result via a single .onChange modifier.
    private var connectivityFingerprint: String {
        [connectionType.rawValue,
         host, port, database, username, password,
         useSSL ? "ssl" : "", useSSL && verifySSLCertificate ? "verify" : "",
         sshEnabled ? "ssh" : "", sshHost, sshPort, sshUser, sshKeyPath, sshPassphrase,
         cloudSQLInstanceConnectionName, useADC ? "adc" : ""].joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Connection" : "New Connection")
                    .font(.headline)
                Spacer()
                if !isEditing && !isCloudSQL {
                    Button("Paste URI") { pasteURI() }
                        .help("Parse a postgresql:// URI from the clipboard and fill in the fields below")
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
            }
            .padding()

            Divider()

            if let uriErr = uriError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(uriErr)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        uriError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
                Divider()
            }

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
                                        Text(color == c ? "✓" : "●")
                                            .foregroundColor(c.color)
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
                    TextField("Notes (optional)", text: $notes)
                        .foregroundStyle(notes.isEmpty ? .secondary : .primary)

                    Picker("Type", selection: $connectionType) {
                        Text("Direct TCP").tag(ConnectionType.direct)
                        Text("Google Cloud SQL").tag(ConnectionType.cloudSQL)
                    }
                    .pickerStyle(.menu)
                }

                if isCloudSQL {
                    // Cloud SQL section
                    Section("Google Cloud SQL") {
                        HStack {
                            TextField("Instance connection name (project:region:instance)",
                                      text: $cloudSQLInstanceConnectionName)
                            Button("Browse…") { showingInstancePicker = true }
                                .buttonStyle(.borderless)
                                .disabled(!gcloudAvailable)
                                .help(gcloudAvailable
                                      ? "Browse Cloud SQL instances from gcloud"
                                      : "gcloud not found. Install Google Cloud SDK.")
                        }
                        HStack {
                            TextField("Database", text: $database)
                            if isLoadingDatabases {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Browse…") {
                                    Task { await fetchDatabases() }
                                }
                                .buttonStyle(.borderless)
                                .disabled(cloudSQLInstanceConnectionName.isEmpty
                                          || !gcloudAvailable)
                                .help(cloudSQLInstanceConnectionName.isEmpty
                                      ? "Select an instance first"
                                      : "List databases on this instance")
                                .popover(isPresented: $showingDatabasePopover, arrowEdge: .trailing) {
                                    DatabasePickerPopover(
                                        databases: availableDatabases,
                                        onSelect: { database = $0; showingDatabasePopover = false }
                                    )
                                }
                            }
                        }
                    }

                    Section("Authentication") {
                        TextField("Username", text: $username)
                        Toggle("Use Application Default Credentials", isOn: $useADC)
                        if !useADC {
                            SecureField("Password", text: $password)
                        } else {
                            Text("Token will be fetched via `gcloud auth print-access-token` at connect time.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Toggle("Read-only", isOn: $isReadOnly)
                    }

                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.green)
                            Text("cloud-sql-proxy encrypts traffic to Cloud SQL. The local connection to the proxy uses plain TCP.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                } else {
                    // Direct TCP sections
                    Section("Server") {
                        HStack {
                            TextField("Host", text: $host)
                            TextField("Port", text: $port)
                                .frame(width: 70)
                                .help("The PostgreSQL server port. Default is 5432.")
                        }
                        TextField("Database", text: $database)
                            .help("The specific database to connect to. Leave blank to connect to the default database (usually your username).")
                    }

                    Section("Authentication") {
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                        Toggle("Use SSL", isOn: $useSSL)
                        if useSSL {
                            Toggle("Verify Certificate", isOn: $verifySSLCertificate)
                                .padding(.leading, 16)
                        }
                        Toggle("Read-only", isOn: $isReadOnly)
                            .help("Prevents any INSERT, UPDATE, DELETE, or DDL statements from executing on this connection.")
                    }

                    Section("SSH Tunnel") {
                        Toggle("Use SSH Tunnel", isOn: $sshEnabled)
                            .help("Route the connection through an SSH server. Useful for databases not exposed to the public internet.")

                        if sshEnabled {
                            HStack {
                                TextField("Host", text: $sshHost)
                                TextField("Port", text: $sshPort)
                                    .frame(width: 70)
                            }
                            TextField("User", text: $sshUser)
                            HStack {
                                TextField("Key Path", text: $sshKeyPath)
                                Button("Browse…") { pickKey() }
                                    .buttonStyle(.borderless)
                            }
                            SecureField("Passphrase", text: $sshPassphrase)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: $showingInstancePicker) {
                CloudSQLInstancePickerSheet { instance in
                    cloudSQLInstanceConnectionName = instance.connectionName
                    cloudSQLProject = instance.project
                    if name.isEmpty { name = instance.name }
                }
            }

            Divider()

            // Footer with test button and result below
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingConnection {
                                ProgressView().controlSize(.mini)
                            }
                            Text(isTestingConnection ? "Testing…" : "Test Connection")
                        }
                        .frame(minWidth: 120)
                    }
                    .disabled({
                        if isCloudSQL { return isTestingConnection || cloudSQLInstanceConnectionName.isEmpty || database.isEmpty || username.isEmpty }
                        return isTestingConnection || host.isEmpty || database.isEmpty || username.isEmpty
                    }())

                    Spacer()
                }

                if let result = testResult {
                    Text(result)
                        .foregroundStyle(result.hasPrefix("✓") ? Color.green : Color.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .frame(width: 480)
        .onChange(of: connectivityFingerprint) { _, _ in testResult = nil }
        .onAppear {
            populate()
            gcloudAvailable = CloudSQLProxy.findBinary("gcloud") != nil
        }
        .onDisappear {
            if let proxy = testProxy {
                Task { await proxy.stop() }
                testProxy = nil
            }
        }
    }

    // MARK: - Actions

    private func populate() {
        guard let c = connection else { return }
        connectionType  = c.connectionType
        name            = c.name
        host            = c.host
        port            = String(c.port)
        database        = c.database
        username        = c.username
        password        = KeychainManager.shared.password(for: c.id) ?? ""
        useSSL                = c.useSSL
        verifySSLCertificate  = c.verifySSLCertificate
        isReadOnly            = c.isReadOnly
        color           = c.color
        sshEnabled      = c.sshEnabled
        sshHost         = c.sshHost
        sshPort         = String(c.sshPort)
        sshUser         = c.sshUser
        sshKeyPath      = c.sshKeyPath
        sshPassphrase   = KeychainManager.shared.sshPassphrase(for: c.id) ?? ""
        notes           = c.notes
        cloudSQLInstanceConnectionName = c.cloudSQLInstanceConnectionName
        cloudSQLProject = c.cloudSQLProject
        useADC          = c.useADC
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
        if isCloudSQL {
            let parts = cloudSQLInstanceConnectionName.split(separator: ":")
            guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else {
                uriError = "Instance connection name must be in the format project:region:instance"
                return
            }
        }
        let portInt    = Int(port) ?? 5432
        let sshPortInt = Int(sshPort) ?? 22
        if let existing = connection {
            var updated          = existing
            updated.connectionType = connectionType
            updated.name         = name
            updated.host         = host
            updated.port         = portInt
            updated.database     = database
            updated.username     = username
            updated.useSSL                = useSSL
            updated.verifySSLCertificate  = verifySSLCertificate
            updated.isReadOnly            = isReadOnly
            updated.color        = color
            updated.sshEnabled   = sshEnabled
            updated.sshHost      = sshHost
            updated.sshPort      = sshPortInt
            updated.sshUser      = sshUser
            updated.sshKeyPath   = sshKeyPath
            updated.notes        = notes
            updated.cloudSQLInstanceConnectionName = cloudSQLInstanceConnectionName
            updated.cloudSQLProject = cloudSQLProject
            updated.useADC       = useADC
            if useADC {
                KeychainManager.shared.deletePassword(for: updated.id)
            } else {
                KeychainManager.shared.setPassword(password, for: updated.id)
            }
            KeychainManager.shared.setSshPassphrase(sshPassphrase, for: updated.id)
            appState.updateConnection(updated)
        } else {
            var new = Connection(
                name: name, host: host, port: portInt,
                database: database, username: username,
                useSSL: useSSL, verifySSLCertificate: verifySSLCertificate,
                isReadOnly: isReadOnly, color: color
            )
            new.connectionType = connectionType
            new.sshEnabled  = sshEnabled
            new.sshHost     = sshHost
            new.sshPort     = sshPortInt
            new.notes       = notes
            new.sshUser     = sshUser
            new.sshKeyPath  = sshKeyPath
            new.cloudSQLInstanceConnectionName = cloudSQLInstanceConnectionName
            new.cloudSQLProject = cloudSQLProject
            new.useADC      = useADC
            if useADC {
                KeychainManager.shared.deletePassword(for: new.id)
            } else {
                KeychainManager.shared.setPassword(password, for: new.id)
            }
            KeychainManager.shared.setSshPassphrase(sshPassphrase, for: new.id)
            appState.addConnection(new)
        }
        dismiss()
    }

    private func pasteURI() {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            uriError = "Clipboard is empty."
            return
        }
        guard let parsed = parsePostgresURI(trimmed) else {
            uriError = "Could not parse a PostgreSQL URI from the clipboard. Expected format: postgresql://user:pass@host:5432/database"
            return
        }
        host     = parsed.host
        port     = parsed.port
        database = parsed.database
        username = parsed.username
        password = parsed.password
        useSSL               = parsed.useSSL
        verifySSLCertificate = parsed.verifySSLCertificate
        uriError = nil
        testResult = nil
    }

    private struct ParsedURI {
        var host: String
        var port: String
        var database: String
        var username: String
        var password: String
        var useSSL: Bool
        var verifySSLCertificate: Bool
    }

    private func parsePostgresURI(_ raw: String) -> ParsedURI? {
        guard var comps = URLComponents(string: raw),
              comps.scheme == "postgresql" || comps.scheme == "postgres"
        else { return nil }

        // Require an explicit, non-empty host — don't silently fall back to localhost
        guard let h = comps.host, !h.isEmpty else { return nil }
        let p  = comps.port.map { String($0) } ?? "5432"
        // Path is "/dbname" — strip the leading slash
        let db = comps.path.hasPrefix("/") ? String(comps.path.dropFirst()) : comps.path
        let u  = comps.user ?? ""
        let pw = comps.password ?? ""

        // sslmode query param mapping:
        //   verify-full / verify-ca → useSSL = true, verifySSLCertificate = true
        //   require / prefer / allow → useSSL = true, verifySSLCertificate = false
        //   disable / (absent)      → useSSL = false, verifySSLCertificate = false
        let sslmode = (comps.queryItems?.first(where: { $0.name == "sslmode" })?.value ?? "").lowercased()
        let ssl    = !sslmode.isEmpty && sslmode != "disable"
        let verify = sslmode == "verify-full" || sslmode == "verify-ca"

        guard !db.isEmpty else { return nil }
        return ParsedURI(host: h, port: p, database: db, username: u, password: pw, useSSL: ssl, verifySSLCertificate: verify)
    }

    private func testConnection() async {
        let startedFingerprint = connectivityFingerprint
        isTestingConnection = true
        testResult = nil

        if isCloudSQL {
            await testCloudSQLConnection(startedFingerprint: startedFingerprint)
        } else {
            await testDirectConnection(startedFingerprint: startedFingerprint)
        }

        isTestingConnection = false
    }

    private func testDirectConnection(startedFingerprint: String) async {
        var info = Connection(
            name: name, host: host, port: Int(port) ?? 5432,
            database: database, username: username,
            useSSL: useSSL, verifySSLCertificate: verifySSLCertificate, isReadOnly: isReadOnly
        )
        info.sshEnabled = sshEnabled
        info.sshHost    = sshHost
        info.sshPort    = Int(sshPort) ?? 22
        info.sshUser    = sshUser
        info.sshKeyPath = sshKeyPath

        var tunnel: SSHTunnel? = nil

        do {
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
                if connectivityFingerprint == startedFingerprint { testResult = "✓ Connected successfully" }
            } catch {
                if connectivityFingerprint == startedFingerprint { testResult = "✗ \(friendlyError(error))" }
            }
        } catch {
            if connectivityFingerprint == startedFingerprint { testResult = "✗ \(friendlyError(error))" }
        }

        if let tunnel { await tunnel.stop() }
    }

    private func fetchDatabases() async {
        guard !isLoadingDatabases else { return }
        isLoadingDatabases = true
        availableDatabases = []
        defer { isLoadingDatabases = false }

        // Parse project:region:instance — project is the first component.
        let parts = cloudSQLInstanceConnectionName.split(separator: ":").map(String.init)
        let instanceName = parts.last ?? cloudSQLInstanceConnectionName
        let project = parts.first ?? cloudSQLProject

        guard let gcloud = CloudSQLProxy.findBinary("gcloud") else { return }

        do {
            let dbs = try await Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: gcloud)
                var args = ["sql", "databases", "list",
                            "--instance", instanceName,
                            "--format=json"]
                if !project.isEmpty { args += ["--project", project] }
                proc.arguments = args
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError  = FileHandle.nullDevice
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { return [String]() }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    return [String]()
                }
                return json.compactMap { $0["name"] as? String }
                           .filter { $0 != "information_schema" && $0 != "performance_schema" && $0 != "mysql" && $0 != "sys" }
                           .sorted()
            }.value
            availableDatabases = dbs
            if !dbs.isEmpty { showingDatabasePopover = true }
        } catch {
            // Silently fall through — user can still type the name manually.
        }
    }

    private func testCloudSQLConnection(startedFingerprint: String) async {
        let proxy = CloudSQLProxy()
        testProxy = proxy
        defer { testProxy = nil }
        var effectiveInfo = Connection(
            name: name, host: "127.0.0.1", port: 5432,
            database: database, username: username,
            useSSL: false, verifySSLCertificate: false, isReadOnly: isReadOnly
        )
        do {
            let localPort = try await proxy.start(
                instanceConnectionName: cloudSQLInstanceConnectionName,
                useIAMAuth: useADC
            )
            effectiveInfo.port = localPort

            let pw: String
            if useADC {
                pw = try await Task.detached { try CloudSQLProxy.fetchADCToken() }.value
            } else {
                pw = password
            }

            let client = DatabaseClient()
            do {
                try await client.connect(to: effectiveInfo, password: pw)
                await client.disconnect()
                if connectivityFingerprint == startedFingerprint { testResult = "✓ Connected successfully" }
            } catch {
                if connectivityFingerprint == startedFingerprint { testResult = "✗ \(friendlyError(error))" }
            }
        } catch {
            if connectivityFingerprint == startedFingerprint { testResult = "✗ \(friendlyError(error))" }
        }
        await proxy.stop()
    }
}

// MARK: - Database picker popover

private struct DatabasePickerPopover: View {
    let databases: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose Database")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(databases, id: \.self) { db in
                        Button {
                            onSelect(db)
                        } label: {
                            Text(db)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.001))
                        Divider()
                    }
                }
            }
        }
        .frame(width: 200)
        .frame(maxHeight: 240)
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
            let underlying = (psql.underlying?.localizedDescription ?? "").lowercased()
            if underlying.contains("certificate") || underlying.contains("tls") || underlying.contains("ssl") || underlying.contains("handshake") {
                return "SSL handshake failed. Try disabling certificate verification."
            }
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
