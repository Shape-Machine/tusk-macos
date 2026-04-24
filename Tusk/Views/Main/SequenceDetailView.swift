import SwiftUI

// MARK: - Sequence Detail Tab

struct SequenceDetailView: View {
    let schema: String
    let sequenceName: String
    let client: DatabaseClient
    let connection: Connection

    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    @State private var detail: SequenceDetail? = nil
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var setValueText: String = ""
    @State private var actionError: String? = nil

    private var isReadOnly: Bool { connection.isReadOnly }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        metadataSection(detail: detail)
                        if !isReadOnly {
                            Divider().padding(.vertical, 12)
                            actionsSection(detail: detail)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView {
                    Label("Failed to Load Sequence", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError ?? "Could not retrieve details for \(schema).\(sequenceName).")
                } actions: {
                    Button("Retry") { Task { await reload() } }
                        .buttonStyle(.bordered)
                }
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
        .task { await reload() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.number")
                .foregroundStyle(.secondary)
            Text("\(schema).\(sequenceName)")
                .font(.system(size: contentFontSize, weight: .semibold, design: contentFontDesign.design))
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Metadata section

    private func metadataSection(detail: SequenceDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Properties")
                .font(.system(size: contentFontSize - 1, weight: .semibold, design: contentFontDesign.design))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            row("Data type",    detail.dataType)
            row("Last value",   detail.lastValue.map { String($0) } ?? "Never used")
            row("Start value",  String(detail.startValue))
            row("Min value",    String(detail.minValue))
            row("Max value",    String(detail.maxValue))
            row("Increment",    String(detail.increment))
            row("Cycles",       detail.cycleOption ? "Yes" : "No")
            if let table = detail.ownedByTable, let col = detail.ownedByColumn {
                row("Owned by",  "\(table).\(col)")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: contentFontSize, design: contentFontDesign.design))
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions section

    private func actionsSection(detail: SequenceDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.system(size: contentFontSize - 1, weight: .semibold, design: contentFontDesign.design))
                .foregroundStyle(.secondary)

            // Set value
            let parsedValue = Int64(setValueText)
            let outOfRange = parsedValue.map { $0 < detail.minValue || $0 > detail.maxValue } ?? false
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("New value…", text: $setValueText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .font(.system(size: contentFontSize, design: contentFontDesign.design))
                    Button("Set Value") { setvalue() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(parsedValue == nil || outOfRange)
                }
                if outOfRange {
                    Text("Must be between \(detail.minValue) and \(detail.maxValue)")
                        .font(.system(size: contentFontSize - 2))
                        .foregroundStyle(.orange)
                }
            }

            // Reset to 1
            Button("Reset to 1…") { resetToOne() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)

            // Drop
            Button("Drop Sequence…") { dropSequence() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
        }
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        loadError = nil
        do {
            detail = try await client.sequenceDetail(schema: schema, name: sequenceName)
        } catch {
            detail = nil
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Mutations

    private func setvalue() {
        guard let newVal = Int64(setValueText),
              let detail,
              newVal >= detail.minValue && newVal <= detail.maxValue else { return }
        Task {
            do {
                let regclass = "\(quoteIdentifier(schema)).\(quoteIdentifier(sequenceName))".replacingOccurrences(of: "'", with: "''")
                _ = try await client.query("SELECT setval('\(regclass)', \(newVal));")
                setValueText = ""
                await reload()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func resetToOne() {
        let alert = NSAlert()
        alert.messageText = "Reset \"\(sequenceName)\" to 1?"
        alert.informativeText = "The next call to nextval() will return 1. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                let regclass = "\(quoteIdentifier(schema)).\(quoteIdentifier(sequenceName))".replacingOccurrences(of: "'", with: "''")
                _ = try await client.query("SELECT setval('\(regclass)', 1, false);")
                await reload()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func dropSequence() {
        let alert = NSAlert()
        alert.messageText = "Drop Sequence \"\(sequenceName)\"?"
        alert.informativeText = "This permanently removes the sequence. Any columns using it via nextval() will fail on the next insert."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Drop Sequence")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                _ = try await client.query("DROP SEQUENCE \(quoteIdentifier(schema)).\(quoteIdentifier(sequenceName));")
                try? await appState.refreshSchema(for: connection)
                if let tab = appState.openTabs.first(where: {
                    if case .sequence(let cid, let s, let n) = $0.kind { return cid == connection.id && s == schema && n == sequenceName }
                    return false
                }) { appState.closeDetailTab(tab.id) }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}
