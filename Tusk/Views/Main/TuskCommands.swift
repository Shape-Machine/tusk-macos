import SwiftUI

struct TuskCommands: Commands {
    let appState: AppState

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Tusk") {
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appState.isShowingSettings.toggle()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("New Connection…") {
                appState.isAddingConnection = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Close Tab") {
                if let tabID = appState.activeDetailTabID {
                    appState.closeDetailTab(tabID)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(appState.activeDetailTabID == nil)
        }

        CommandGroup(after: .windowArrangement) {
            Button("Show Next Tab") { appState.activateNextTab() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(appState.openTabs.count < 2)

            Button("Show Previous Tab") { appState.activatePreviousTab() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(appState.openTabs.count < 2)
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
