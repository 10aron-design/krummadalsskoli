import Foundation

// MARK: - Search configuration the user controls in Settings.

/// How the user wants to hunt for flights. Persisted as JSON in UserDefaults.
struct SearchConfig: Codable, Equatable {
    /// IATA codes we depart from. Iceland = Keflavik (KEF).
    var originCodes: [String] = ["KEF"]
    /// IATA codes we want to land at. Japan = Tokyo (both airports) + Osaka.
    var destinationCodes: [String] = ["TYO", "OSA"]

    /// Flexible window: scan every departure date inside this month range.
    /// Stored as the first day of each month.
    var earliestDeparture: Date = SearchConfig.firstOfMonth(monthsFromNow: 1)
    var latestDeparture: Date = SearchConfig.firstOfMonth(monthsFromNow: 4)

    /// Trip length range in nights. We try a few lengths inside this band.
    var minTripNights: Int = 10
    var maxTripNights: Int = 18

    var adults: Int = 1
    var nonStopOnly: Bool = false
    var preferredCurrency: String = "EUR"

    /// A deal must be at or below this price to be "good" and worth a ping.
    var maxPrice: Double = 700
    /// If true, maxPrice is compared PER PERSON (price ÷ adults), matching how
    /// Skyscanner shows fares. If false, it's the total for the whole party.
    var maxPriceIsPerPerson: Bool = true

    /// Sampling step in days across the month window. Smaller = more API calls.
    var samplingStepDays: Int = 7

    /// Hard cap on searches per scan. Protects your monthly quota: the scan
    /// samples evenly across the date window to fit within this many searches.
    /// NOTE: each search costs ~2–5 RapidAPI calls (Skyscanner needs polling),
    /// and free tiers are tiny (~100/month), so keep this low.
    var maxRequestsPerScan: Int = 6

    // MARK: Trap rules

    /// Reject layovers longer than this many hours.
    var maxLayoverHours: Double = 6
    /// Reject whole journeys longer than this many hours.
    var maxTotalTravelHours: Double = 30
    /// Reject more than this many stops on a single leg.
    var maxStopsPerLeg: Int = 2
    /// Treat self-transfer / mixed-airline itineraries as traps. OFF by default:
    /// Iceland→Japan almost always connects on partner carriers, so this caused
    /// false positives that hid genuinely good connecting deals.
    var rejectSelfTransfer: Bool = false
    /// Treat overnight airport layovers as traps.
    var rejectOvernightLayover: Bool = false

    static func firstOfMonth(monthsFromNow: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .month, value: monthsFromNow, to: Date()) ?? Date()
        let comps = cal.dateComponents([.year, .month], from: base)
        return cal.date(from: comps) ?? base
    }
}

// MARK: - A trap is anything that makes a "cheap" flight secretly miserable.

enum TrapReason: String, Codable, CaseIterable {
    case longLayover            = "Painfully long layover"
    case tooManyStops           = "Too many stops"
    case marathonJourney        = "Marathon total travel time"
    case selfTransfer           = "Unconnected airlines (self-transfer risk)"
    case overnightLayover       = "Overnight airport sleepover"
}

// MARK: - Normalized result we show + store.

struct FlightDeal: Codable, Identifiable, Equatable {
    var id: String                 // stable hash of route+dates+price
    var origin: String
    var destination: String
    var departureDate: Date
    var returnDate: Date?
    var price: Double
    var currency: String
    var stopsOutbound: Int
    var stopsInbound: Int
    var totalTravelHours: Double   // worst (longest) of the two legs
    var longestLayoverHours: Double
    var airlines: [String]         // distinct carrier codes across the trip
    var deepLinkInfo: String       // human-readable booking hint
    var foundAt: Date

    /// Filled in by TrapDetector. Empty == clean deal.
    var trapReasons: [TrapReason] = []

    var isTrap: Bool { !trapReasons.isEmpty }
    var nights: Int? {
        guard let r = returnDate else { return nil }
        return Calendar.current.dateComponents([.day], from: departureDate, to: r).day
    }
}

// MARK: - Tiny date helpers used across the app.

extension Date {
    var ymd: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: self)
    }
    var prettyDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: self)
    }
}

// MARK: - Provider-neutral "raw" offer.
// Every flight provider (Skyscanner, etc.) maps its JSON into these structs,
// so the search + trap-detection logic never has to care where data came from.

struct RawOffer {
    var price: RawPrice
    var itineraries: [RawItinerary]      // [0] = outbound, [1] = inbound
    var validatingAirlineCodes: [String]?
}

struct RawPrice {
    var amount: Double
    var currency: String?
}

struct RawItinerary {
    var duration: String                 // ISO-8601 like "PT14H30M"
    var segments: [RawSegment]
}

struct RawSegment {
    var departure: RawPoint
    var arrival: RawPoint
    var carrierCode: String              // marketing carrier (e.g. "FI")
    var operating: RawOperating?
    var numberOfStops: Int?
}

struct RawOperating { var carrierCode: String? }

struct RawPoint {
    var iataCode: String
    var at: String                       // "2026-08-12T16:40:00"
}
