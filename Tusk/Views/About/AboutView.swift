import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    @State private var updateStatus: UpdateStatus = .idle

    var body: some View {
        VStack(spacing: 0) {
            // App identity
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)

                Text("Tusk")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            // Update section
            VStack(spacing: 12) {
                updateStatusView

                Button(action: checkForUpdates) {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        .frame(minWidth: 160)
                }
                .disabled(updateStatus == .checking)
                .controlSize(.regular)
            }
            .padding(20)
        }
        .frame(width: 320)
    }

    // MARK: - Update status

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView("Checking for updates…")
                .controlSize(.small)
        case .upToDate:
            Label("You're on the latest version.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .available(let version):
            VStack(spacing: 6) {
                Label("Version \(version) is available.", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Link("View on GitHub",
                     destination: URL(string: "https://github.com/Shape-Machine/tusk-macos/releases/latest")!)
                    .font(.caption)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Update check (manual only — never called automatically)

    @MainActor
    private func checkForUpdates() {
        updateStatus = .checking
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/Shape-Machine/tusk-macos/releases/latest")!
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    updateStatus = .error("GitHub returned an error (HTTP \(http.statusCode)).")
                    return
                }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                updateStatus = isNewer(latest, than: appVersion) ? .available(latest) : .upToDate
            } catch {
                updateStatus = .error("Could not reach GitHub. Check your connection.")
            }
        }
    }

    /// Compares two semver strings component-by-component.
    private func isNewer(_ version: String, than current: String) -> Bool {
        let lhs = version.split(separator: ".").compactMap { Int($0) }
        let rhs = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - Update status model

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(String)
    case error(String)
}

// MARK: - GitHub API model

private struct GitHubRelease: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
