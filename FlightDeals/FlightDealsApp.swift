import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct FlightDealsApp: App {
    // Single source of truth for the whole app.
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register the daily background refresh task as early as possible.
        BackgroundScheduler.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    NotificationManager.shared.requestAuthorization()
                    BackgroundScheduler.shared.scheduleDailyRefresh()
                }
        }
        .onChange(of: scenePhase) { phase in
            // Re-arm the background task whenever we leave the foreground.
            if phase == .background {
                BackgroundScheduler.shared.scheduleDailyRefresh()
            }
        }
    }
}
