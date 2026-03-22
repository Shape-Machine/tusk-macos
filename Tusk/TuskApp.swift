import SwiftUI

@main
struct TuskApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            TuskCommands(appState: appState)
        }

        Window("About Tusk", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Sponsor Tusk", id: "sponsor") {
            SponsorView()
        }
        .windowResizability(.contentSize)

        Window("Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
