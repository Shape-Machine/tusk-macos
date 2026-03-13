import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tusk")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

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
