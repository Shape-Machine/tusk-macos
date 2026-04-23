import SwiftUI

// MARK: - ImportPgpassSheet

struct ImportPgpassSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [SelectableEntry] = []
    @State private var loadError: String? = nil
    @State private var isLoading = true
    @State private var fileURL: URL = PgpassImporter.defaultURL

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from .pgpass")
                        .font(.headline)
                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Choose File…") { pickFile() }
                    .controlSize(.small)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Cannot Read File",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Importable Entries",
                    systemImage: "doc.badge.ellipsis",
                    description: Text("The file contains no concrete connection entries.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(entries) {
                    TableColumn("") { entry in
                        Toggle("", isOn: bindingFor(entry))
                            .labelsHidden()
                            .disabled(entry.status == .duplicate && !entry.selected)
                    }
                    .width(24)
                    TableColumn("Connection") { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.pgpassEntry.suggestedName)
                                .font(.system(.body, design: .monospaced))
                            if entry.status == .duplicate {
                                Text("Already exists")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    TableColumn("Host") { entry in
                        Text(entry.pgpassEntry.host.isEmpty ? "*" : entry.pgpassEntry.host)
                            .foregroundStyle(entry.pgpassEntry.host.isEmpty ? .secondary : .primary)
                    }
                    TableColumn("Port") { entry in
                        Text("\(entry.pgpassEntry.port)")
                    }
                    .width(48)
                    TableColumn("Database") { entry in
                        Text(entry.pgpassEntry.database.isEmpty ? "*" : entry.pgpassEntry.database)
                            .foregroundStyle(entry.pgpassEntry.database.isEmpty ? .secondary : .primary)
                    }
                    TableColumn("User") { entry in
                        Text(entry.pgpassEntry.username.isEmpty ? "*" : entry.pgpassEntry.username)
                            .foregroundStyle(entry.pgpassEntry.username.isEmpty ? .secondary : .primary)
                    }
                }
                .alternatingRowBackgrounds()
            }

            Divider()

            // Footer
            HStack {
                if !entries.isEmpty {
                    let selectedCount = entries.filter(\.selected).count
                    Text("\(selectedCount) of \(entries.count) selected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { performImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(entries.filter(\.selected).isEmpty)
            }
            .padding()
        }
        .frame(width: 720, height: 420)
        .onAppear { load(url: fileURL) }
    }

    // MARK: - Load

    private func load(url: URL) {
        isLoading = true
        loadError = nil
        entries = []
        fileURL = url

        do {
            let parsed = try PgpassImporter.parse(url: url)
            entries = parsed.map { entry in
                let isDuplicate = appState.connections.contains {
                    $0.host == entry.host &&
                    $0.port == entry.port &&
                    $0.database == entry.database &&
                    $0.username == entry.username
                }
                return SelectableEntry(
                    pgpassEntry: entry,
                    selected: !isDuplicate,
                    status: isDuplicate ? .duplicate : .new
                )
            }
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Import

    private func performImport() {
        for entry in entries where entry.selected {
            let conn = Connection(
                name:     entry.pgpassEntry.suggestedName,
                host:     entry.pgpassEntry.host,
                port:     entry.pgpassEntry.port,
                database: entry.pgpassEntry.database,
                username: entry.pgpassEntry.username
            )

            if entry.status == .duplicate,
               let existing = appState.connections.first(where: {
                   $0.host == conn.host &&
                   $0.port == conn.port &&
                   $0.database == conn.database &&
                   $0.username == conn.username
               }) {
                // Overwrite password only — keep existing connection metadata
                KeychainManager.shared.setPassword(entry.pgpassEntry.password, for: existing.id)
            } else {
                appState.addConnection(conn)
                KeychainManager.shared.setPassword(entry.pgpassEntry.password, for: conn.id)
            }
        }
        dismiss()
    }

    // MARK: - File picker

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Select .pgpass file"
        panel.allowedContentTypes = []   // any file
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    // MARK: - Binding helper

    private func bindingFor(_ entry: SelectableEntry) -> Binding<Bool> {
        Binding(
            get: { entry.selected },
            set: { newValue in
                if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[idx].selected = newValue
                }
            }
        )
    }
}

// MARK: - SelectableEntry

private struct SelectableEntry: Identifiable {
    let id = UUID()
    let pgpassEntry: PgpassEntry
    var selected: Bool
    var status: Status

    enum Status { case new, duplicate }
}
