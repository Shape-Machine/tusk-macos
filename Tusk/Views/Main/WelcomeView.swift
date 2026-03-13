import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                Text("Welcome to Tusk")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("A minimal, privacy-first PostgreSQL client.")
                    .foregroundStyle(.secondary)
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
