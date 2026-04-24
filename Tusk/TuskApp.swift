import SwiftUI
import UserNotifications

@main
struct TuskApp: App {
    @State private var appState = AppState()
    private let notificationDelegate = QueryNotificationDelegate()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                }
                .onReceive(NotificationCenter.default.publisher(for: .tuskActivateQueryTab)) { note in
                    guard let tabID = note.userInfo?["tabID"] as? UUID,
                          let detailTab = appState.openTabs.first(where: {
                              guard case .queryEditor(let qid) = $0.kind else { return false }
                              return appState.queryTabs.first(where: { $0.id == qid })?.id == tabID
                          }) else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    appState.activeDetailTabID = detailTab.id
                }
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

// MARK: - Notification delegate

extension Notification.Name {
    static let tuskActivateQueryTab = Notification.Name("tusk.activateQueryTab")
}

/// Handles taps on query-completion notifications — posts a notification to activate the tab.
final class QueryNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let tabIDString = response.notification.request.content.userInfo["tabID"] as? String,
              let tabID = UUID(uuidString: tabIDString) else { return }
        NotificationCenter.default.post(name: .tuskActivateQueryTab, object: nil, userInfo: ["tabID": tabID])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Don't show banner when app is frontmost — the user can see the result directly
        completionHandler([])
    }
}
