import SwiftUI

struct TuskCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Connection…") {
                appState.isAddingConnection = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Database") {
            Button("New Query Tab") {
                if let connection = appState.selectedConnection {
                    appState.openQueryTab(for: connection)
                }
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(appState.selectedConnection == nil)

            Divider()

            Button("Refresh Schema") {
                Task {
                    if let connection = appState.selectedConnection {
                        try? await appState.refreshSchema(for: connection)
                    }
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.selectedConnection == nil)

            Divider()

            Button("Disconnect") {
                if let connection = appState.selectedConnection {
                    appState.disconnect(connection)
                }
            }
            .disabled(appState.selectedConnection == nil || !appState.isConnected(appState.selectedConnection!))
        }
    }
}
