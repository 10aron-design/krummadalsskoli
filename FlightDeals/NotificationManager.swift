import Foundation
import UserNotifications

/// Wraps local-notification permission + firing deal alerts.
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// One summary notification for the best new deal found in a scan.
    func notifyBestDeal(_ deal: FlightDeal, totalGoodDeals: Int) {
        let content = UNMutableNotificationContent()
        content.title = "✈️ Iceland → Japan deal!"
        let price = "\(Int(deal.price)) \(deal.currency)"
        let route = "\(deal.origin)→\(deal.destination)"
        let nights = deal.nights.map { " · \($0) nights" } ?? ""
        content.body = "\(price)  \(route)  \(deal.departureDate.prettyDate)\(nights)"
            + (totalGoodDeals > 1 ? "  (+\(totalGoodDeals - 1) more)" : "")
        content.sound = .default
        content.badge = NSNumber(value: totalGoodDeals)

        let req = UNNotificationRequest(
            identifier: "deal-\(deal.id)",
            content: content,
            trigger: nil) // fire immediately
        UNUserNotificationCenter.current().add(req)
    }

    func notifyScanFinishedNoDeals() {
        // Quiet by design: we don't nag when there's nothing good.
    }
}
