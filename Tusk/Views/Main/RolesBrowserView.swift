import SwiftUI

struct RolesBrowserView: View {
    let client: DatabaseClient
    let connection: Connection
    @Environment(AppState.self) private var appState

    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var selectedRoleName: String? = nil
    @State private var memberships: [String] = []       // roles that selectedRole is a member of
    @State private var members: [String] = []           // roles that are members of selectedRole
    @State private var isLoadingMemberships = false

    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    private var roles: [RoleInfo] { appState.connectionRoles[connection.id] ?? [] }
    private var users: [RoleInfo] { roles.filter { $0.canLogin } }
    private var roleOnly: [RoleInfo] { roles.filter { !$0.canLogin } }

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
            }
            .frame(minHeight: 180)

            if selectedRoleName != nil {
                membershipPanel
                    .frame(minHeight: 80, maxHeight: 200)
            }
        }
        .task { await refresh() }
        .onChange(of: selectedRoleName) { _, name in
            guard let name else { memberships = []; members = []; return }
            Task { await loadMemberships(for: name) }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connection.color.color)
                .frame(width: 8, height: 8)
            Text(connection.name)
                .font(.system(size: contentFontSize, weight: .semibold, design: contentFontDesign.design))
            Spacer()
            if isLoading { ProgressView().controlSize(.small) }
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Main table

    @ViewBuilder
    private var content: some View {
        if let error {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if roles.isEmpty && !isLoading {
            ContentUnavailableView("No Roles", systemImage: "person.2",
                description: Text("No roles were found for this connection."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(roles, selection: $selectedRoleName) {
                TableColumn("Name") { role in
                    HStack(spacing: 5) {
                        Image(systemName: role.canLogin ? "person" : "person.2")
                            .foregroundStyle(role.canLogin ? .primary : .secondary)
                            .font(.system(size: contentFontSize - 1))
                        Text(role.name)
                            .font(.system(size: contentFontSize, design: contentFontDesign.design))
                    }
                }

                TableColumn("Super") { role in
                    boolCell(role.superuser)
                }
                .width(52)

                TableColumn("Inherit") { role in
                    boolCell(role.inherit)
                }
                .width(58)

                TableColumn("Cr. Role") { role in
                    boolCell(role.createRole)
                }
                .width(58)

                TableColumn("Cr. DB") { role in
                    boolCell(role.createDB)
                }
                .width(52)

                TableColumn("Login") { role in
                    boolCell(role.canLogin)
                }
                .width(46)

                TableColumn("Repl.") { role in
                    boolCell(role.replication)
                }
                .width(44)

                TableColumn("Conn Limit") { role in
                    Text(role.connLimit == -1 ? "∞" : "\(role.connLimit)")
                        .font(.system(size: contentFontSize, design: .monospaced))
                        .foregroundStyle(role.connLimit == -1 ? .tertiary : .primary)
                }
                .width(72)
            }
        }
    }

    @ViewBuilder
    private func boolCell(_ value: Bool) -> some View {
        if value {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
                .font(.system(size: contentFontSize - 1, weight: .semibold))
        } else {
            Text("—")
                .foregroundStyle(.quaternary)
                .font(.system(size: contentFontSize))
        }
    }

    // MARK: - Membership detail panel

    private var membershipPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                if isLoadingMemberships {
                    ProgressView().controlSize(.small).padding(12)
                } else {
                    memberColumn(title: "Member of", items: memberships)
                    Divider().frame(maxHeight: .infinity)
                    memberColumn(title: "Has members", items: members)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func memberColumn(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: contentFontSize - 1, weight: .semibold, design: contentFontDesign.design))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            if items.isEmpty {
                Text("None")
                    .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(items, id: \.self) { name in
                    Text(name)
                        .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Data loading

    private func refresh() async {
        isLoading = true
        error = nil
        await appState.loadRoles(for: connection)
        if appState.connectionRoles[connection.id] == nil {
            error = "Failed to load roles."
        }
        isLoading = false
    }

    private func loadMemberships(for roleName: String) async {
        isLoadingMemberships = true
        let escaped = roleName.replacingOccurrences(of: "'", with: "''")

        // Roles that this role is a member of
        let memberOfResult = try? await client.query("""
            SELECT r.rolname FROM pg_auth_members m
            JOIN pg_roles r ON r.oid = m.roleid
            JOIN pg_roles u ON u.oid = m.member
            WHERE u.rolname = '\(escaped)'
            ORDER BY r.rolname
            """)
        memberships = memberOfResult?.rows.compactMap { $0.first?.displayValue } ?? []

        // Roles that are members of this role
        let membersResult = try? await client.query("""
            SELECT u.rolname FROM pg_auth_members m
            JOIN pg_roles r ON r.oid = m.roleid
            JOIN pg_roles u ON u.oid = m.member
            WHERE r.rolname = '\(escaped)'
            ORDER BY u.rolname
            """)
        members = membersResult?.rows.compactMap { $0.first?.displayValue } ?? []

        isLoadingMemberships = false
    }
}
