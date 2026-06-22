import Foundation

/// Turns raw provider offers into clean FlightDeals, scans flexible date
/// windows, and stamps trap reasons on each deal.
struct FlightSearchService {
    let client: FlightProvider
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

    /// First-of-month dates covering the whole flexible window. The calendar
    /// engine fetches one cheap calendar per month.
    func candidateMonths() -> [Date] {
        let cal = Calendar.current
        func firstOf(_ date: Date) -> Date {
            cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        }
        var months: [Date] = []
        var m = firstOf(config.earliestDeparture)
        let end = firstOf(config.latestDeparture)
        while m <= end {
            months.append(m)
            guard let next = cal.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return months
    }

    /// Trip lengths to try inside the min/max nights band (up to 3 samples).
    func candidateTripLengths() -> [Int] {
        let lo = max(1, config.minTripNights)
        let hi = max(lo, config.maxTripNights)
        if lo == hi { return [lo] }
        let mid = (lo + hi) / 2
        return Array(Set([lo, mid, hi])).sorted()
    }

    /// One unit of work: a single round-trip API search.
    struct ScanJob {
        let origin: String
        let destination: String
        let departure: Date
        let nights: Int
    }

    /// Every job the flexible window *could* probe, before budgeting.
    func allJobs() -> [ScanJob] {
        let cal = Calendar.current
        var jobs: [ScanJob] = []
        for origin in config.originCodes {
            for destination in config.destinationCodes {
                for dep in candidateDepartures() {
                    for nights in candidateTripLengths() {
                        if cal.date(byAdding: .day, value: nights, to: dep) != nil {
                            jobs.append(ScanJob(origin: origin, destination: destination,
                                                departure: dep, nights: nights))
                        }
                    }
                }
            }
        }
        return jobs
    }

    /// Trims the job list down to the call budget by sampling evenly across
    /// the whole window (so we still cover the full date range, just sparser).
    func budgetedJobs() -> [ScanJob] {
        let jobs = allJobs()
        let budget = max(1, config.maxRequestsPerScan)
        guard jobs.count > budget else { return jobs }
        let stride = Double(jobs.count) / Double(budget)
        var picked: [ScanJob] = []
        var i = 0.0
        while Int(i) < jobs.count && picked.count < budget {
            picked.append(jobs[Int(i)])
            i += stride
        }
        return picked
    }

    /// Entry point for a scan. Uses Skyscanner's price calendar when enabled
    /// (far cheaper on quota, finds the true cheapest days), otherwise falls
    /// back to the legacy even-sampling scan.
    func runFullScan(onProgress: ((String) -> Void)? = nil) async -> (deals: [FlightDeal], error: String?) {
        if config.usePriceCalendar {
            return await runCalendarScan(onProgress: onProgress)
        }
        return await runSampledScan(onProgress: onProgress)
    }

    // MARK: Calendar engine — cheapest-day-first

    /// Phase 1: one price-calendar call per route×month → cheapest fare per day.
    /// Phase 2: full round-trip detail searches on only the cheapest days, so we
    /// match Skyscanner's numbers while spending a fraction of the quota.
    func runCalendarScan(onProgress: ((String) -> Void)? = nil) async -> (deals: [FlightDeal], error: String?) {
        let cal = Calendar.current
        var lastError: String?
        let floorDate = max(Date(), config.earliestDeparture)

        // Phase 1 — gather cheapest-per-day prices across the window.
        struct DayCandidate { let origin: String; let destination: String; let date: Date; let price: Double }
        var candidates: [DayCandidate] = []
        var coveredMonths = Set<String>()      // "yyyy-MM" already returned by a call
        func monthKey(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month], from: d)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        }

        let months = candidateMonths()
        outer: for origin in config.originCodes {
            for destination in config.destinationCodes {
                coveredMonths.removeAll()      // coverage is per-route
                for month in months {
                    // A single calendar call often returns several months; skip
                    // any month we've already seen to save quota.
                    if coveredMonths.contains(monthKey(month)) { continue }
                    onProgress?("Calendar \(origin)→\(destination) \(month.ymd.prefix(7))…")
                    do {
                        let days = try await client.priceCalendar(
                            origin: origin, destination: destination,
                            month: month, currency: config.preferredCurrency)
                        for day in days {
                            coveredMonths.insert(monthKey(day.date))
                            if day.date >= floorDate && day.date <= config.latestDeparture {
                                candidates.append(DayCandidate(
                                    origin: origin, destination: destination,
                                    date: day.date, price: day.price))
                            }
                        }
                        // Mark the requested month covered even if it returned nothing.
                        coveredMonths.insert(monthKey(month))
                    } catch {
                        let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        lastError = msg
                        if msg.contains("429") || msg.lowercased().contains("quota") { break outer }
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }

        // Rank the cheapest days, de-duplicated per route+date.
        var seenDay = Set<String>()
        let cheapestDays = candidates
            .sorted { $0.price < $1.price }
            .filter { seenDay.insert("\($0.origin)-\($0.destination)-\($0.date.ymd)").inserted }

        // No calendar data? Fall back to the sampling scan rather than show nothing.
        guard !cheapestDays.isEmpty else {
            let fallback = await runSampledScan(onProgress: onProgress)
            return (fallback.deals, fallback.error ?? lastError)
        }

        // Phase 2 — detail-check only the cheapest days (budgeted).
        let detailBudget = max(1, min(config.calendarCandidateDays, config.maxRequestsPerScan))
        let nights = candidateTripLengths()
        let midNights = nights[nights.count / 2]

        var results: [FlightDeal] = []
        for (index, day) in cheapestDays.prefix(detailBudget).enumerated() {
            guard let ret = cal.date(byAdding: .day, value: midNights, to: day.date) else { continue }
            onProgress?("[\(index + 1)/\(detailBudget)] \(day.origin)→\(day.destination) \(day.date.ymd) (from \(Int(day.price)) \(config.preferredCurrency))")
            do {
                let raw = try await client.searchRoundTrip(
                    origin: day.origin, destination: day.destination,
                    departure: day.date, returnDate: ret,
                    adults: config.adults, nonStop: config.nonStopOnly,
                    currency: config.preferredCurrency, max: 15)
                for offer in raw {
                    results.append(Self.normalize(
                        offer, origin: day.origin, destination: day.destination,
                        departure: day.date, returnDate: ret, config: config))
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                lastError = msg
                if msg.contains("429") || msg.lowercased().contains("quota") { break }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        var seen = Set<String>()
        let unique = results
            .sorted { $0.price < $1.price }
            .filter { seen.insert($0.id).inserted }
        return (unique, lastError)
    }

    // MARK: Legacy even-sampling engine (used when the calendar is disabled).

    /// Full flexible scan, capped at `config.maxRequestsPerScan` API calls so a
    /// single run can never blow your monthly quota. Returns every deal found,
    /// traps included. `onProgress` is optional UI feedback.
    func runSampledScan(onProgress: ((String) -> Void)? = nil) async -> (deals: [FlightDeal], error: String?) {
        var results: [FlightDeal] = []
        var lastError: String?
        let cal = Calendar.current

        let jobs = budgetedJobs()
        for (index, job) in jobs.enumerated() {
            guard let ret = cal.date(byAdding: .day, value: job.nights, to: job.departure) else { continue }
            onProgress?("[\(index + 1)/\(jobs.count)] \(job.origin)→\(job.destination)  \(job.departure.ymd) (+\(job.nights)n)")
            do {
                let raw = try await client.searchRoundTrip(
                    origin: job.origin, destination: job.destination,
                    departure: job.departure, returnDate: ret,
                    adults: config.adults, nonStop: config.nonStopOnly,
                    currency: config.preferredCurrency, max: 15)
                for offer in raw {
                    results.append(Self.normalize(
                        offer, origin: job.origin, destination: job.destination,
                        departure: job.departure, returnDate: ret, config: config))
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                lastError = msg
                // If we hit the quota/rate limit, stop immediately — hammering
                // it further is pointless and just wastes calls.
                if msg.contains("429") || msg.lowercased().contains("quota") { break }
            }
            // Be polite to the rate limiter.
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        // Cheapest first, de-duplicated by id.
        var seen = Set<String>()
        let unique = results
            .sorted { $0.price < $1.price }
            .filter { seen.insert($0.id).inserted }
        return (unique, lastError)
    }

    /// The price we compare against maxPrice — per person or total per config.
    static func comparablePrice(_ deal: FlightDeal, config: SearchConfig) -> Double {
        config.maxPriceIsPerPerson ? deal.price / Double(max(1, config.adults)) : deal.price
    }

    /// Clean deals at or under the user's max price = worth a ping.
    static func goodDeals(from deals: [FlightDeal], config: SearchConfig) -> [FlightDeal] {
        deals.filter { !$0.isTrap && comparablePrice($0, config: config) <= config.maxPrice }
    }
}
