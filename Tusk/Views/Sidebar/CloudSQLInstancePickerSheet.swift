import SwiftUI

// MARK: - CloudSQLInstance model

struct CloudSQLInstance: Identifiable, Hashable, Sendable {
    var id: String { connectionName }
    let connectionName: String   // project:region:instance
    let project: String
    let region: String
    let name: String
    let databaseVersion: String
}

// MARK: - CloudSQLInstancePickerSheet

struct CloudSQLInstancePickerSheet: View {
    /// Called with the chosen instance when the user taps Select.
    let onSelect: @Sendable (CloudSQLInstance) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var instances: [CloudSQLInstance] = []
    @State private var filterText = ""
    @State private var selectedID: String? = nil   // matches CloudSQLInstance.id (connectionName)
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    private var selectedInstance: CloudSQLInstance? {
        guard let id = selectedID else { return nil }
        return filtered.first(where: { $0.id == id }) ?? instances.first(where: { $0.id == id })
    }

    var filtered: [CloudSQLInstance] {
        guard !filterText.isEmpty else { return instances }
        let f = filterText.lowercased()
        return instances.filter {
            $0.name.lowercased().contains(f)     ||
            $0.project.lowercased().contains(f)  ||
            $0.region.lowercased().contains(f)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Browse Cloud SQL Instances")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Select") {
                    if let s = selectedInstance { onSelect(s); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedInstance == nil)
            }
            .padding()

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading instances from gcloud…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let err = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(err)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if instances.isEmpty {
                Text("No Cloud SQL instances found in the active gcloud project.\nRun `gcloud config set project <project>` to switch projects.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                // Filter bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Filter…", text: $filterText)
                        .textFieldStyle(.plain)
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                List(filtered, selection: $selectedID) { instance in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name)
                            .font(.body)
                        HStack(spacing: 6) {
                            Text(instance.project)
                            Text("·").foregroundStyle(.tertiary)
                            Text(instance.region)
                            Text("·").foregroundStyle(.tertiary)
                            Text(instance.databaseVersion)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .onDoubleClick {
                    if let s = selectedInstance { onSelect(s); dismiss() }
                }
            }
        }
        .frame(width: 480, height: 380)
        .task { await load() }
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            instances = try await fetchInstances()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchInstances() async throws -> [CloudSQLInstance] {
        try await Task.detached {
            guard let gcloud = CloudSQLProxy.findBinary("gcloud") else {
                throw CloudSQLProxyError.gcloudNotFound
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: gcloud)
            proc.arguments     = ["sql", "instances", "list", "--format=json"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError  = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw CloudSQLListError.commandFailed
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try Self.parseInstances(from: data)
        }.value
    }

    private nonisolated static func parseInstances(from data: Data) throws -> [CloudSQLInstance] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CloudSQLListError.parseError
        }
        return json.compactMap { item -> CloudSQLInstance? in
            guard
                let connectionName  = item["connectionName"] as? String,
                let name            = item["name"] as? String,
                let project         = item["project"] as? String,
                let region          = item["region"] as? String,
                let dbVersion       = item["databaseVersion"] as? String
            else { return nil }
            return CloudSQLInstance(
                connectionName: connectionName,
                project: project,
                region: region,
                name: name,
                databaseVersion: dbVersion
            )
        }
        .sorted { $0.name < $1.name }
    }
}

// MARK: - CloudSQLListError

private enum CloudSQLListError: LocalizedError {
    case commandFailed
    case parseError

    var errorDescription: String? {
        switch self {
        case .commandFailed:
            return "gcloud sql instances list failed. Ensure you are authenticated: gcloud auth login"
        case .parseError:
            return "Failed to parse gcloud output."
        }
    }
}

// MARK: - Double-click modifier

private extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        simultaneousGesture(TapGesture(count: 2).onEnded { action() })
    }
}
