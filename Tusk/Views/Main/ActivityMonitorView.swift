import SwiftUI

struct ActivityMonitorView: View {
    let client: DatabaseClient
    let connection: Connection

    @State private var entries: [ActivityEntry] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var selectedPID: Int? = nil

    // Cancel / terminate confirmation
    @State private var confirmAction: BackendAction? = nil

    // Error alert for cancel/terminate
    @State private var actionError: String? = nil

    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    private enum BackendAction: Identifiable {
        case cancel(Int)
        case terminate(Int)
        var id: Int {
            switch self { case .cancel(let p): return p; case .terminate(let p): return p + 1_000_000 }
        }
        var title: String {
            switch self { case .cancel: return "Cancel Query?"; case .terminate: return "Terminate Backend?" }
        }
        var message: String {
            switch self {
            case .cancel:    return "This will cancel the current query for this backend. The connection will remain open."
            case .terminate: return "This will forcibly close the backend connection. Any open transaction will be rolled back."
            }
        }
        var buttonLabel: String {
            switch self { case .cancel: return "Cancel Query"; case .terminate: return "Terminate" }
        }
        var pid: Int {
            switch self { case .cancel(let p): return p; case .terminate(let p): return p }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .task { await refresh() }
        // Auto-refresh every 5 seconds
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
        .alert(confirmAction?.title ?? "", isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } })) {
            Button(confirmAction?.buttonLabel ?? "", role: .destructive) {
                if let action = confirmAction { Task { await perform(action) } }
            }
            Button("Cancel", role: .cancel) { confirmAction = nil }
        } message: {
            Text(confirmAction?.message ?? "")
        }
        .alert("Action Failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
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
            if isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty && !isLoading {
            ContentUnavailableView("No Active Backends", systemImage: "waveform.path.ecg",
                description: Text("No other sessions are currently active."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(entries, selection: $selectedPID) {
                TableColumn("PID") { entry in
                    Text(String(entry.pid))
                        .font(.system(size: contentFontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(60)

                TableColumn("Application") { entry in
                    Text(entry.applicationName.isEmpty ? "—" : entry.applicationName)
                        .font(.system(size: contentFontSize, design: contentFontDesign.design))
                }

                TableColumn("State") { entry in
                    stateLabel(entry.state)
                }
                .width(130)

                TableColumn("Wait") { entry in
                    if let wt = entry.waitEventType, let we = entry.waitEvent {
                        Text("\(wt): \(we)")
                            .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .width(140)

                TableColumn("Duration") { entry in
                    if let d = entry.durationSeconds {
                        Text(formatDuration(d))
                            .font(.system(size: contentFontSize, design: .monospaced))
                            .foregroundStyle(d > 30 ? .orange : .primary)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .width(80)

                TableColumn("Query") { entry in
                    let display = entry.query.isEmpty ? "—" : redactSQL(entry.query)
                    Text(display)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: contentFontSize - 1, design: .monospaced))
                        .foregroundStyle(entry.query.isEmpty ? .tertiary : .primary)
                }
            }
            .font(.system(size: contentFontSize, design: contentFontDesign.design))
            .contextMenu(forSelectionType: Int.self) { pids in
                if let pid = pids.first {
                    Button("Cancel Query for PID \(pid)") {
                        confirmAction = .cancel(pid)
                    }
                    Button("Terminate Backend for PID \(pid)", role: .destructive) {
                        confirmAction = .terminate(pid)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func stateLabel(_ state: String) -> some View {
        let (color, label): (Color, String) = switch state {
        case "active":              (.green,  "Active")
        case "idle":                (.secondary, "Idle")
        case "idle in transaction": (.orange, "Idle in Txn")
        case "idle in transaction (aborted)": (.red, "Idle (Aborted)")
        case "fastpath function call": (.blue, "Fastpath")
        case "disabled":            (.secondary, "Disabled")
        default:                    (.secondary, state.isEmpty ? "—" : state)
        }
        return Text(label)
            .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
            .foregroundStyle(color)
    }

    /// Replace plaintext passwords in SQL so they never appear in the UI.
    /// Covers: PASSWORD 'literal'  PASSWORD NULL
    private func redactSQL(_ sql: String) -> String {
        guard sql.localizedCaseInsensitiveContains("password") else { return sql }
        let pattern = #"(?i)\bPASSWORD\s+'[^']*'"#
        let redacted = sql.replacingOccurrences(of: pattern, with: "PASSWORD '***'",
                                                options: .regularExpression)
        return redacted
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60  { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }

    // MARK: - Data loading

    private func refresh() async {
        isLoading = true
        error = nil
        do {
            entries = try await client.activityMonitor()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func perform(_ action: BackendAction) async {
        confirmAction = nil
        do {
            switch action {
            case .cancel(let pid):    try await client.cancelBackend(pid: pid)
            case .terminate(let pid): try await client.terminateBackend(pid: pid)
            }
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
