import Foundation

/// Turns raw Amadeus offers into clean FlightDeals, scans flexible date
/// windows, and stamps trap reasons on each deal.
struct FlightSearchService {
    let client: AmadeusClient
    let config: SearchConfig

    /// ISO-8601 duration ("PT14H30M") -> hours as a Double.
    static func hours(fromISODuration iso: String) -> Double {
        var h = 0.0, m = 0.0
        var number = ""
        for ch in iso {
            if ch.isNumber { number.append(ch) }
            else if ch == "H" { h = Double(number) ?? 0; number = "" }
            else if ch == "M" { m = Double(number) ?? 0; number = "" }
            else { number = "" } // skip P, T, D etc.
        }
        return h + m / 60.0
    }

    private static func parseAt(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }

    /// Layover hours = gaps between consecutive segments on one leg.
    private static func layovers(_ itin: RawItinerary) -> [Double] {
        var gaps: [Double] = []
        let segs = itin.segments
        guard segs.count > 1 else { return gaps }
        for i in 0..<(segs.count - 1) {
            guard let arr = parseAt(segs[i].arrival.at),
                  let dep = parseAt(segs[i + 1].departure.at) else { continue }
            gaps.append(dep.timeIntervalSince(arr) / 3600.0)
        }
        return gaps
    }

    /// True if any layover crosses local night hours (rough: spans 01:00–05:00).
    private static func hasOvernightLayover(_ itin: RawItinerary) -> Bool {
        let segs = itin.segments
        guard segs.count > 1 else { return false }
        for i in 0..<(segs.count - 1) {
            guard let arr = parseAt(segs[i].arrival.at),
                  let dep = parseAt(segs[i + 1].departure.at) else { continue }
            if dep.timeIntervalSince(arr) < 3 * 3600 { continue } // short = fine
            let cal = Calendar(identifier: .gregorian)
            // Walk the gap hour by hour; if we touch 1am–5am, it's an overnighter.
            var t = arr
            while t < dep {
                let hr = cal.component(.hour, from: t)
                if hr >= 1 && hr <= 5 { return true }
                t = t.addingTimeInterval(3600)
            }
        }
        return false
    }

    /// Distinct marketing+operating carriers across the whole offer.
    private static func carriers(_ offer: RawOffer) -> [String] {
        var set = Set<String>()
        for itin in offer.itineraries {
            for seg in itin.segments {
                set.insert(seg.carrierCode)
                if let op = seg.operating?.carrierCode { set.insert(op) }
            }
        }
        return set.sorted()
    }

    /// The heart of "is this a trap?". Pure + testable.
    static func trapReasons(for offer: RawOffer, config: SearchConfig) -> [TrapReason] {
        var reasons: [TrapReason] = []

        let allLayovers = offer.itineraries.flatMap { layovers($0) }
        let worstLayover = allLayovers.max() ?? 0
        if worstLayover > config.maxLayoverHours { reasons.append(.longLayover) }

        let maxStops = offer.itineraries.map { max(0, $0.segments.count - 1) }.max() ?? 0
        if maxStops > config.maxStopsPerLeg { reasons.append(.tooManyStops) }

        let worstLeg = offer.itineraries.map { hours(fromISODuration: $0.duration) }.max() ?? 0
        if worstLeg > config.maxTotalTravelHours { reasons.append(.marathonJourney) }

        if config.rejectSelfTransfer {
            // A clean trip is usually one airline (or codeshare partners).
            // More than one distinct carrier on a multi-segment leg => risk.
            let multiSegment = offer.itineraries.contains { $0.segments.count > 1 }
            if multiSegment && carriers(offer).count > 1 { reasons.append(.selfTransfer) }
        }

        if config.rejectOvernightLayover {
            if offer.itineraries.contains(where: { hasOvernightLayover($0) }) {
                reasons.append(.overnightLayover)
            }
        }
        return reasons
    }

    private static func normalize(_ offer: RawOffer,
                                  origin: String,
                                  destination: String,
                                  departure: Date,
                                  returnDate: Date,
                                  config: SearchConfig) -> FlightDeal {
        let out = offer.itineraries.first
        let back = offer.itineraries.count > 1 ? offer.itineraries[1] : nil
        let stopsOut = max(0, (out?.segments.count ?? 1) - 1)
        let stopsIn = max(0, (back?.segments.count ?? 1) - 1)
        let worstLeg = offer.itineraries.map { hours(fromISODuration: $0.duration) }.max() ?? 0
        let worstLayover = offer.itineraries.flatMap { layovers($0) }.max() ?? 0
        let lines = carriers(offer)

        // Stable, human-readable id (String.hashValue is randomized per run).
        let idSeed = "\(origin)-\(destination)-\(departure.ymd)-\(returnDate.ymd)-\(Int(offer.price.amount))"
        var deal = FlightDeal(
            id: idSeed,
            origin: origin,
            destination: destination,
            departureDate: departure,
            returnDate: returnDate,
            price: offer.price.amount,
            currency: offer.price.currency ?? config.preferredCurrency,
            stopsOutbound: stopsOut,
            stopsInbound: stopsIn,
            totalTravelHours: worstLeg,
            longestLayoverHours: worstLayover,
            airlines: lines,
            deepLinkInfo: "Search \(origin)→\(destination) on \(departure.ymd), back \(returnDate.ymd)",
            foundAt: Date()
        )
        deal.trapReasons = trapReasons(for: offer, config: config)
        return deal
    }

    // MARK: Flexible window scan

    /// Builds the list of departure dates to probe across the month window.
    func candidateDepartures() -> [Date] {
        var dates: [Date] = []
        let cal = Calendar.current
        var d = config.earliestDeparture
        while d <= config.latestDeparture {
            if d > Date() { dates.append(d) }   // never search the past
            d = cal.date(byAdding: .day, value: max(1, config.samplingStepDays), to: d) ?? d.addingTimeInterval(86400)
        }
        return dates
    }

    /// Trip lengths to try inside the min/max nights band (up to 3 samples).
    func candidateTripLengths() -> [Int] {
        let lo = max(1, config.minTripNights)
        let hi = max(lo, config.maxTripNights)
        if lo == hi { return [lo] }
        let mid = (lo + hi) / 2
        return Array(Set([lo, mid, hi])).sorted()
    }

    /// Full flexible scan. Returns every deal found, traps included
    /// (caller decides what to notify on). `onProgress` is optional UI feedback.
    func runFullScan(onProgress: ((String) -> Void)? = nil) async -> (deals: [FlightDeal], error: String?) {
        var results: [FlightDeal] = []
        var lastError: String?
        let cal = Calendar.current

        for origin in config.originCodes {
            for destination in config.destinationCodes {
                for dep in candidateDepartures() {
                    for nights in candidateTripLengths() {
                        guard let ret = cal.date(byAdding: .day, value: nights, to: dep) else { continue }
                        onProgress?("\(origin)→\(destination)  \(dep.ymd) (+\(nights)n)")
                        do {
                            let raw = try await client.searchRoundTrip(
                                origin: origin, destination: destination,
                                departure: dep, returnDate: ret,
                                adults: config.adults, nonStop: config.nonStopOnly,
                                currency: config.preferredCurrency)
                            for offer in raw {
                                results.append(Self.normalize(
                                    offer, origin: origin, destination: destination,
                                    departure: dep, returnDate: ret, config: config))
                            }
                        } catch {
                            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                        // Be polite to the rate limiter.
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
            }
        }

        // Cheapest first, de-duplicated by id.
        var seen = Set<String>()
        let unique = results
            .sorted { $0.price < $1.price }
            .filter { seen.insert($0.id).inserted }
        return (unique, lastError)
    }

    /// Clean deals at or under the user's max price = worth a ping.
    static func goodDeals(from deals: [FlightDeal], config: SearchConfig) -> [FlightDeal] {
        deals.filter { !$0.isTrap && $0.price <= config.maxPrice }
    }
}
