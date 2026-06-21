import Foundation
import Combine

/// Observable app state: config, credentials, found deals, scan status.
/// Persists everything to UserDefaults so background scans share it.
@MainActor
final class AppStore: ObservableObject {
    @Published var config: SearchConfig { didSet { persist(config, key: Keys.config) } }
    @Published var creds: AmadeusCredentials { didSet { persist(creds, key: Keys.creds); rebuildClient() } }
    @Published private(set) var deals: [FlightDeal] { didSet { persist(deals, key: Keys.deals) } }

    @Published var isScanning = false
    @Published var progressText = ""
    @Published var lastScanDate: Date?
    @Published var lastError: String?

    private var client: AmadeusClient

    enum Keys {
        static let config = "search.config"
        static let creds  = "amadeus.creds"
        static let deals  = "found.deals"
        static let lastScan = "last.scan.date"
    }

    init() {
        let cfg = Self.load(SearchConfig.self, key: Keys.config) ?? SearchConfig()
        let cr  = Self.load(AmadeusCredentials.self, key: Keys.creds) ?? AmadeusCredentials()
        self.config = cfg
        self.creds  = cr
        self.deals  = Self.load([FlightDeal].self, key: Keys.deals) ?? []
        self.lastScanDate = UserDefaults.standard.object(forKey: Keys.lastScan) as? Date
        self.client = AmadeusClient(creds: cr)
    }

    private func rebuildClient() {
        let c = creds
        Task { await client.update(creds: c) }
    }

    /// Run a full flexible scan, update state, and ping on the best clean deal.
    func runScan() async {
        guard !isScanning else { return }
        guard creds.isConfigured else {
            lastError = AmadeusError.notConfigured.errorDescription
            return
        }
        isScanning = true
        lastError = nil
        defer { isScanning = false }

        let service = FlightSearchService(client: client, config: config)
        let (found, err) = await service.runFullScan { [weak self] text in
            Task { @MainActor in self?.progressText = text }
        }

        let goodNew = FlightSearchService.goodDeals(from: found, config: config)
        self.deals = found.sorted { $0.price < $1.price }
        self.lastError = err
        self.lastScanDate = Date()
        UserDefaults.standard.set(Date(), forKey: Keys.lastScan)

        if let best = goodNew.first {
            NotificationManager.shared.notifyBestDeal(best, totalGoodDeals: goodNew.count)
        }
    }

    var goodDeals: [FlightDeal] { FlightSearchService.goodDeals(from: deals, config: config) }
    var trapDeals: [FlightDeal] { deals.filter { $0.isTrap } }

    // MARK: Persistence helpers

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
