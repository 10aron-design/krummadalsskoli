import Foundation
import BackgroundTasks

/// Schedules + runs the once-a-day background flight scan via BGTaskScheduler.
/// The identifier here MUST match the one in Info.plist (BGTaskSchedulerPermittedIdentifiers).
final class BackgroundScheduler {
    static let shared = BackgroundScheduler()
    private init() {}

    static let taskID = "com.flightdeals.dailyScan"

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.handle(task: task)
        }
    }

    /// Ask iOS to wake us roughly once a day. iOS decides the exact moment.
    func scheduleDailyRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 24, to: Date())
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common in the Simulator — fine on a real device.
            print("BG schedule failed: \(error)")
        }
    }

    private func handle(task: BGAppRefreshTask) {
        // Always queue the next day's scan first.
        scheduleDailyRefresh()

        let work = Task {
            await Self.runStandaloneScan()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Reads config/creds straight from UserDefaults so it works without UI.
    static func runStandaloneScan() async {
        guard
            let credsData = UserDefaults.standard.data(forKey: AppStore.Keys.creds),
            let creds = try? JSONDecoder().decode(AmadeusCredentials.self, from: credsData),
            creds.isConfigured
        else { return }

        let cfg = (UserDefaults.standard.data(forKey: AppStore.Keys.config)
            .flatMap { try? JSONDecoder().decode(SearchConfig.self, from: $0) }) ?? SearchConfig()

        let client = AmadeusClient(creds: creds)
        let service = FlightSearchService(client: client, config: cfg)
        let (found, _) = await service.runFullScan()

        // Persist results for the UI to pick up next launch.
        if let data = try? JSONEncoder().encode(found.sorted { $0.price < $1.price }) {
            UserDefaults.standard.set(data, forKey: AppStore.Keys.deals)
        }
        UserDefaults.standard.set(Date(), forKey: AppStore.Keys.lastScan)

        let good = FlightSearchService.goodDeals(from: found, config: cfg)
        if let best = good.first {
            NotificationManager.shared.notifyBestDeal(best, totalGoodDeals: good.count)
        }
    }
}
