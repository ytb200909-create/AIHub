import SwiftUI

@main
struct AIHubApp: App {
    @StateObject private var conversations = ConversationStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(conversations)
                .environmentObject(settings)
        }
    }
}
