import SwiftUI

// MARK: - Role Detail Tab

struct RoleDetailView: View {
    let connectionID: UUID
    let roleName: String
    let client: DatabaseClient
    let connection: Connection

    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    @State private var memberships: [String] = []
    @State private var members: [String] = []
    @State private var allRoleNames: [String] = []
    @State private var isLoadingMemberships = false
    @State private var membershipError: String? = nil
    @State private var actionError: String? = nil

    private var role: RoleInfo? {
        appState.connectionRoles[connectionID]?.first(where: { $0.name == roleName })
    }

    private var isSuperuser: Bool {
        appState.superuserConnections.contains(connectionID) && !connection.isReadOnly
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let role {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        attributesSection(role: role)
                        Divider().padding(.vertical, 8)
                        membershipSection
                        if isSuperuser {
                            Divider().padding(.vertical, 8)
                            actionsSection(role: role)
                        }
                    }
                    .padding(16)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .task {
            if appState.connectionRoles[connectionID] == nil {
                await appState.loadRoles(for: connection)
            }
            await loadMemberships()
            allRoleNames = (appState.connectionRoles[connectionID] ?? []).map(\.name)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connection.color.color)
                .frame(width: 8, height: 8)
            Image(systemName: role?.canLogin == true ? "person" : "person.2")
                .foregroundStyle(.secondary)
            Text(roleName)
                .font(.system(size: contentFontSize, weight: .semibold, design: contentFontDesign.design))
            if role?.superuser == true {
                Text("superuser")
                    .font(.system(size: contentFontSize - 2, design: contentFontDesign.design))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quinary, in: Capsule())
            }
            Spacer()
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Attributes section

    @ViewBuilder
    private func attributesSection(role: RoleInfo) -> some View {
        SectionHeader("Attributes")
        VStack(spacing: 0) {
            attributeRow("Superuser", value: role.superuser) {
                await alter(role, "SUPERUSER", "NOSUPERUSER", current: role.superuser)
            }
            Divider()
            attributeRow("Can login", value: role.canLogin) {
                await alter(role, "LOGIN", "NOLOGIN", current: role.canLogin)
            }
            Divider()
            attributeRow("Create DB", value: role.createDB) {
                await alter(role, "CREATEDB", "NOCREATEDB", current: role.createDB)
            }
            Divider()
            attributeRow("Create role", value: role.createRole) {
                await alter(role, "CREATEROLE", "NOCREATEROLE", current: role.createRole)
            }
            Divider()
            attributeRow("Inherit", value: role.inherit) {
                await alter(role, "INHERIT", "NOINHERIT", current: role.inherit)
            }
            Divider()
            attributeRow("Replication", value: role.replication) {
                await alter(role, "REPLICATION", "NOREPLICATION", current: role.replication)
            }
            Divider()
            connLimitRow(role: role)
            Divider()
            validUntilRow(role: role)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
    }

    @ViewBuilder
    private func attributeRow(_ label: String, value: Bool, onToggle: @escaping () async -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: contentFontSize, design: contentFontDesign.design))
                .foregroundStyle(.primary)
            Spacer()
            if isSuperuser {
                Toggle("", isOn: Binding(
                    get: { value },
                    set: { _ in Task { await onToggle() } }
                ))
                .labelsHidden()
            } else {
                Image(systemName: value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(value ? Color.green : Color.secondary.opacity(0.4))
                    .font(.system(size: contentFontSize))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func connLimitRow(role: RoleInfo) -> some View {
        HStack {
            Text("Connection limit")
                .font(.system(size: contentFontSize, design: contentFontDesign.design))
            Spacer()
            if isSuperuser {
                ConnLimitEditor(current: role.connLimit, fontSize: contentFontSize) { newLimit in
                    await run("ALTER ROLE \(quoteIdentifier(role.name)) CONNECTION LIMIT \(newLimit);")
                    await refresh()
                }
            } else {
                Text(role.connLimit == -1 ? "∞" : "\(role.connLimit)")
                    .font(.system(size: contentFontSize, design: .monospaced))
                    .foregroundStyle(role.connLimit == -1 ? .tertiary : .primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func validUntilRow(role: RoleInfo) -> some View {
        HStack {
            Text("Valid until")
                .font(.system(size: contentFontSize, design: contentFontDesign.design))
            Spacer()
            if isSuperuser {
                ValidUntilEditor(current: role.validUntil, fontSize: contentFontSize) { newValue in
                    let clause = newValue.map { "'\($0)'" } ?? "'infinity'"
                    await run("ALTER ROLE \(quoteIdentifier(role.name)) VALID UNTIL \(clause);")
                    await refresh()
                }
            } else {
                Text(role.validUntil ?? "∞")
                    .font(.system(size: contentFontSize, design: contentFontDesign.design))
                    .foregroundStyle(role.validUntil == nil ? .tertiary : .primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Membership section

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Membership")
            HStack(alignment: .top, spacing: 12) {
                membershipColumn(
                    title: "Member of",
                    items: memberships,
                    addHelp: "Grant membership in a role",
                    onAdd: { grantMembership(type: .memberOf) },
                    onRemove: { revokeMembership(roleName: $0, type: .memberOf) }
                )
                Divider()
                membershipColumn(
                    title: "Has members",
                    items: members,
                    addHelp: "Grant a role membership here",
                    onAdd: { grantMembership(type: .hasMember) },
                    onRemove: { revokeMembership(roleName: $0, type: .hasMember) }
                )
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        }
    }

    private enum MembershipType { case memberOf, hasMember }

    @ViewBuilder
    private func membershipColumn(title: String, items: [String], addHelp: String, onAdd: @escaping () -> Void, onRemove: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: contentFontSize - 1, weight: .semibold, design: contentFontDesign.design))
                    .foregroundStyle(.secondary)
                Spacer()
                if isSuperuser {
                    Button { onAdd() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: contentFontSize - 2))
                    }
                    .buttonStyle(.plain)
                    .help(addHelp)
                }
            }

            if isLoadingMemberships {
                ProgressView().controlSize(.small)
            } else if let err = membershipError {
                Text(err)
                    .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if items.isEmpty {
                Text("None")
                    .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(items, id: \.self) { name in
                    HStack {
                        Image(systemName: "person")
                            .font(.system(size: contentFontSize - 2))
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                        Spacer()
                        if isSuperuser {
                            Button { onRemove(name) } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: contentFontSize - 2))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Actions section (superuser only)

    @ViewBuilder
    private func actionsSection(role: RoleInfo) -> some View {
        SectionHeader("Actions")
        HStack(spacing: 10) {
            Button("Rename…") { renameRole(role) }
            Button("Set Password…") { setPassword(role) }
            Spacer()
            Button("Drop Role…") { dropRole(role) }
                .foregroundStyle(.red)
        }
        .font(.system(size: contentFontSize, design: contentFontDesign.design))
    }

    // MARK: - Data

    private func refresh() async {
        await appState.loadRoles(for: connection)
        await loadMemberships()
        allRoleNames = (appState.connectionRoles[connectionID] ?? []).map(\.name)
    }

    private func loadMemberships() async {
        isLoadingMemberships = true
        membershipError = nil
        let escaped = roleName.replacingOccurrences(of: "'", with: "''")

        async let memberOfResult = client.query("""
            SELECT r.rolname FROM pg_auth_members m
            JOIN pg_roles r ON r.oid = m.roleid
            JOIN pg_roles u ON u.oid = m.member
            WHERE u.rolname = '\(escaped)'
            ORDER BY r.rolname
            """)
        async let membersResult = client.query("""
            SELECT u.rolname FROM pg_auth_members m
            JOIN pg_roles r ON r.oid = m.roleid
            JOIN pg_roles u ON u.oid = m.member
            WHERE r.rolname = '\(escaped)'
            ORDER BY u.rolname
            """)

        do {
            memberships = try await memberOfResult.rows.compactMap { $0.first?.displayValue }
            members     = try await membersResult.rows.compactMap { $0.first?.displayValue }
        } catch {
            membershipError = error.localizedDescription
        }
        isLoadingMemberships = false
    }

    @discardableResult
    private func run(_ sql: String) async -> Bool {
        do {
            _ = try await client.query(sql)
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    private func alter(_ role: RoleInfo, _ onKeyword: String, _ offKeyword: String, current: Bool) async {
        let keyword = current ? offKeyword : onKeyword
        if await run("ALTER ROLE \(quoteIdentifier(role.name)) \(keyword);") {
            await refresh()
        }
    }

    // MARK: - Actions

    private func renameRole(_ role: RoleInfo) {
        let alert = NSAlert()
        alert.messageText = "Rename Role \"\(role.name)\""
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = role.name
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != role.name else { return }
        Task {
            if await run("ALTER ROLE \(quoteIdentifier(role.name)) RENAME TO \(quoteIdentifier(newName));") {
                await appState.loadRoles(for: connection)
                // Close stale tab and open a fresh one under the new name
                if let tab = appState.openTabs.first(where: {
                    if case .role(let cid, let n) = $0.kind { return cid == connectionID && n == roleName }
                    return false
                }) {
                    appState.closeDetailTab(tab.id)
                }
                appState.openRoleTab(for: connection, roleName: newName)
            }
        }
    }

    private func setPassword(_ role: RoleInfo) {
        let alert = NSAlert()
        alert.messageText = "Set Password for \"\(role.name)\""
        alert.informativeText = "Leave blank to remove the password."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let pw = field.stringValue
        Task {
            let clause = pw.isEmpty ? "NULL" : "'\(pw.replacingOccurrences(of: "'", with: "''"))'"
            await run("ALTER ROLE \(quoteIdentifier(role.name)) PASSWORD \(clause);")
        }
    }

    private func dropRole(_ role: RoleInfo) {
        let alert = NSAlert()
        alert.messageText = "Drop Role \"\(role.name)\"?"
        alert.informativeText = "This permanently removes the role. The role must not own any database objects."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Drop Role")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            if await run("DROP ROLE \(quoteIdentifier(role.name));") {
                // Close this tab
                if let tab = appState.openTabs.first(where: {
                    if case .role(let cid, let n) = $0.kind { return cid == connectionID && n == roleName }
                    return false
                }) {
                    appState.closeDetailTab(tab.id)
                }
                await appState.loadRoles(for: connection)
            }
        }
    }

    private func grantMembership(type: MembershipType) {
        let available: [String]
        switch type {
        case .memberOf:  available = allRoleNames.filter { $0 != roleName && !memberships.contains($0) }
        case .hasMember: available = allRoleNames.filter { $0 != roleName && !members.contains($0) }
        }
        guard !available.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = type == .memberOf ? "Grant Membership In…" : "Add Member…"
        alert.addButton(withTitle: "Grant")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        for name in available { popup.addItem(withTitle: name) }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selected = popup.titleOfSelectedItem ?? ""
        guard !selected.isEmpty else { return }

        Task {
            let sql: String
            switch type {
            case .memberOf:  sql = "GRANT \(quoteIdentifier(selected)) TO \(quoteIdentifier(roleName));"
            case .hasMember: sql = "GRANT \(quoteIdentifier(roleName)) TO \(quoteIdentifier(selected));"
            }
            if await run(sql) { await loadMemberships() }
        }
    }

    private func revokeMembership(roleName target: String, type: MembershipType) {
        Task {
            let sql: String
            switch type {
            case .memberOf:  sql = "REVOKE \(quoteIdentifier(target)) FROM \(quoteIdentifier(roleName));"
            case .hasMember: sql = "REVOKE \(quoteIdentifier(roleName)) FROM \(quoteIdentifier(target));"
            }
            if await run(sql) { await loadMemberships() }
        }
    }
}

// MARK: - Inline conn-limit editor

private struct ConnLimitEditor: View {
    let current: Int
    let fontSize: Double
    let onCommit: (Int) async -> Void

    @State private var editing = false
    @State private var text = ""
    @State private var inputError: String? = nil

    var body: some View {
        if editing {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    TextField("blank = unlimited", text: $text)
                        .font(.system(size: fontSize, design: .monospaced))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commit() }
                        .onChange(of: text) { _, _ in inputError = nil }
                    Button("OK") { commit() }
                        .controlSize(.small)
                    Button("Cancel") {
                        editing = false
                        inputError = nil
                    }
                    .controlSize(.small)
                }
                if let inputError {
                    Text(inputError)
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.red)
                }
            }
        } else {
            HStack(spacing: 4) {
                Text(current == -1 ? "∞" : "\(current)")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(current == -1 ? .tertiary : .primary)
                Button("Edit") {
                    text = current == -1 ? "" : "\(current)"
                    editing = true
                }
                .controlSize(.small)
            }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let v: Int
        if trimmed.isEmpty {
            v = -1
        } else if let parsed = Int(trimmed), parsed >= -1 {
            v = parsed
        } else if let parsed = Int(trimmed), parsed < -1 {
            inputError = "Must be ≥ 0, or blank for unlimited"
            return
        } else {
            inputError = "Enter a whole number, or leave blank for unlimited"
            return
        }
        editing = false
        inputError = nil
        Task { await onCommit(v) }
    }
}

// MARK: - Inline valid-until editor

private struct ValidUntilEditor: View {
    let current: String?
    let fontSize: Double
    let onCommit: (String?) async -> Void

    @State private var editing = false
    @State private var date = Date()
    @State private var noExpiry = true

    var body: some View {
        if editing {
            HStack(spacing: 6) {
                Toggle("No expiry", isOn: $noExpiry)
                    .font(.system(size: fontSize - 1))
                if !noExpiry {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .controlSize(.small)
                }
                Button("OK") { commit() }
                    .controlSize(.small)
                Button("Cancel") { editing = false }
                    .controlSize(.small)
            }
        } else {
            HStack(spacing: 4) {
                Text(current ?? "∞")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(current == nil ? .tertiary : .primary)
                Button("Edit") {
                    noExpiry = current == nil
                    date = current.flatMap { parseDate($0) } ?? Date()
                    editing = true
                }
                .controlSize(.small)
            }
        }
    }

    private func commit() {
        editing = false
        if noExpiry {
            Task { await onCommit(nil) }
        } else {
            let formatted = ISO8601DateFormatter().string(from: date)
            Task { await onCommit(formatted) }
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

// MARK: - Section header helper

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }
}
