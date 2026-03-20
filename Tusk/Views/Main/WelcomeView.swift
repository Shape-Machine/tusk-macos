import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                Text("Welcome to Tusk")
                    .font(.system(size: contentFontSize + 14, weight: .semibold, design: contentFontDesign.design))

                VStack(spacing: 4) {
                    Text("Native MacOS client for PostgreSQL.")
                        .foregroundStyle(.secondary)

                    Text("Zero-telemetry. Privacy-focused.")
                        .foregroundStyle(.tertiary)

                    Text("Minimal. Powerful.")
                        .foregroundStyle(.tertiary)
                }
            }

            if appState.connections.isEmpty {
                Button("Add your first connection") {
                    appState.isAddingConnection = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Select a connection in the sidebar to get started.")
                    .foregroundStyle(.tertiary)
                    .font(.callout)

                VStack(spacing: 6) {
                    shortcutRow("⇧⌘N", "New connection")
                    shortcutRow("⌘T", "New query tab")
                    shortcutRow("⌘↵", "Run query")
                    shortcutRow("⇧⌘↵", "Run current query")
                    shortcutRow("⌘W", "Close tab")
                    shortcutRow("⌘[ / ⌘]", "Previous / next tab")
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func shortcutRow(_ key: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 90, alignment: .center)
            Text(label)
                .font(.system(.caption, design: contentFontDesign.design))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 220)
    }
}
