import Foundation

/// Credentials for the Skyscanner data feed via RapidAPI.
/// Sign up free at https://rapidapi.com, subscribe to the **"Sky-Scrapper"**
/// API, then copy your X-RapidAPI-Key here. No OAuth, no approval wait.
struct SkyscannerCredentials: Codable, Equatable {
    var rapidApiKey: String = ""
    /// The RapidAPI host for the Sky-Scrapper listing. Override only if you
    /// subscribed to a differently-named Skyscanner listing on RapidAPI.
    var rapidApiHost: String = "sky-scrapper.p.rapidapi.com"
    /// Pricing market (point-of-sale country). Skyscanner fares vary a LOT by
    /// market — "IE" matches skyscanner.ie (EUR), which is what most Iceland
    /// users see. Change in Settings if your prices look off.
    var market: String = "IE"
    var locale: String = "en-US"

    var isConfigured: Bool { !rapidApiKey.isEmpty && !rapidApiHost.isEmpty }
}

enum FlightAPIError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding(String)
    case airportNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:          return "Add your RapidAPI key in Settings first."
        case .http(let c, let m):     return "API error \(c): \(m)"
        case .decoding(let m):        return "Could not read API response: \(m)"
        case .airportNotFound(let c): return "Couldn't resolve airport \"\(c)\"."
        }
    }
}

/// The contract the search engine talks to. Swap providers by writing another
/// conformer — the rest of the app doesn't change.
protocol FlightProvider {
    func searchRoundTrip(origin: String,
                         destination: String,
                         departure: Date,
                         returnDate: Date,
                         adults: Int,
                         nonStop: Bool,
                         currency: String,
                         max: Int) async throws -> [RawOffer]
}

/// Talks to Skyscanner through the RapidAPI "Sky-Scrapper" endpoints:
/// 1) resolve each airport code -> (skyId, entityId)
/// 2) round-trip flight search
/// then maps the nested JSON into our provider-neutral RawOffer.
actor SkyscannerClient: FlightProvider {
    private var creds: SkyscannerCredentials
    private var airportCache: [String: AirportID]

    /// Codable airport id pair so we can persist the cache across launches /
    /// background runs and avoid burning quota re-resolving the same airports.
    struct AirportID: Codable { let skyId: String; let entityId: String }
    private static let cacheKey = "skyscanner.airportCache"
    private static let incompletePathKey = "skyscanner.incompletePath"

    /// Known candidate paths for the "poll until complete" endpoint. Different
    /// Sky-Scrapper listings name it differently; we auto-detect which works
    /// and remember it.
    static let incompleteCandidates = [
        "/api/v1/flights/searchIncomplete",
        "/api/v2/flights/searchIncomplete",
        "/api/v1/flights/getFlightDetails",
        "/api/v1/searchIncomplete"
    ]
    /// The candidate confirmed to return HTTP 200, cached across runs.
    private var workingIncompletePath: String?

    init(creds: SkyscannerCredentials) {
        self.creds = creds
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([String: AirportID].self, from: data) {
            self.airportCache = cached
        } else {
            self.airportCache = [:]
        }
        self.workingIncompletePath = UserDefaults.standard.string(forKey: Self.incompletePathKey)
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(airportCache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    func update(creds: SkyscannerCredentials) {
        self.creds = creds
        // Keep the airport cache — codes resolve to the same ids regardless of key.
    }

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard creds.isConfigured else { throw FlightAPIError.notConfigured }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = creds.rapidApiHost
        comps.path = path
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(creds.rapidApiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        req.setValue(creds.rapidApiHost, forHTTPHeaderField: "X-RapidAPI-Host")
        return req
    }

    // MARK: Airport resolution

    private func resolveAirport(_ code: String) async throws -> AirportID {
        if let cached = airportCache[code] { return cached }
        let req = try makeRequest(
            path: "/api/v1/flights/searchAirport",
            query: [.init(name: "query", value: code),
                    .init(name: "locale", value: creds.locale)])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw FlightAPIError.http(0, "no response") }
        guard http.statusCode == 200 else {
            throw FlightAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        // Defensive parse: searchAirport returns { data: [ { skyId, entityId, ... } ] }.
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = obj?["data"] as? [[String: Any]]
        guard let first = arr?.first else { throw FlightAPIError.airportNotFound(code) }
        // skyId / entityId may live at the top level or under navigation.
        let nav = first["navigation"] as? [String: Any]
        let params = nav?["relevantFlightParams"] as? [String: Any]
        let skyId = Self.str(first["skyId"]) ?? Self.str(params?["skyId"])
        let entityId = Self.str(first["entityId"]) ?? Self.str(nav?["entityId"]) ?? Self.str(params?["entityId"])
        guard let skyId, let entityId else { throw FlightAPIError.airportNotFound(code) }
        let pair = AirportID(skyId: skyId, entityId: entityId)
        airportCache[code] = pair
        saveCache()
        return pair
    }

    // MARK: Round-trip search

    /// Outcome of one full search (initial call + any polling).
    struct SearchResult {
        var offers: [RawOffer]
        var status: String
        var httpCode: Int
        var rawHead: String
        var calls: Int
        var note: String?
    }

    /// Sky-Scrapper's searchFlights returns `status: incomplete` with a
    /// sessionId and NO itineraries on the first call. We must poll
    /// `searchIncomplete` with that sessionId until results arrive (or we give
    /// up). This does the whole dance and reports how many calls it cost.
    private func performSearch(origin: String, destination: String,
                               departure: Date, returnDate: Date,
                               adults: Int, currency: String,
                               maxPolls: Int = 4) async throws -> SearchResult {
        let from = try await resolveAirport(origin)
        let to = try await resolveAirport(destination)

        let req = try makeRequest(
            path: "/api/v1/flights/searchFlights",
            query: [
                .init(name: "originSkyId", value: from.skyId),
                .init(name: "destinationSkyId", value: to.skyId),
                .init(name: "originEntityId", value: from.entityId),
                .init(name: "destinationEntityId", value: to.entityId),
                .init(name: "date", value: departure.ymd),
                .init(name: "returnDate", value: returnDate.ymd),
                .init(name: "cabinClass", value: "economy"),
                .init(name: "adults", value: String(adults)),
                .init(name: "sortBy", value: "best"),
                .init(name: "currency", value: currency),
                .init(name: "market", value: creds.market),
                .init(name: "countryCode", value: creds.market)
            ])
        var calls = 1
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw FlightAPIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }

        var lastData = data
        var offers = Self.parseOffers(data: data, currency: currency)
        var status = Self.contextStatus(data: data) ?? "unknown"
        var note: String?

        // Poll the "incomplete" endpoint until itineraries show up. We try the
        // known candidate paths until one returns 200, then reuse that path.
        if offers.isEmpty, let sessionId = Self.sessionId(data: data) {
            func pollQuery() -> [URLQueryItem] {
                [.init(name: "sessionId", value: sessionId),
                 .init(name: "currency", value: currency),
                 .init(name: "market", value: creds.market),
                 .init(name: "countryCode", value: creds.market)]
            }
            pollRounds: for _ in 0..<maxPolls {
                if status == "complete" { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                let candidates = workingIncompletePath.map { [$0] } ?? Self.incompleteCandidates
                var got200 = false
                for path in candidates {
                    let pollReq = try makeRequest(path: path, query: pollQuery())
                    let (d2, r2) = try await URLSession.shared.data(for: pollReq)
                    calls += 1
                    let c2 = (r2 as? HTTPURLResponse)?.statusCode ?? 0
                    if c2 == 200 {
                        if workingIncompletePath != path {
                            workingIncompletePath = path
                            UserDefaults.standard.set(path, forKey: Self.incompletePathKey)
                        }
                        lastData = d2
                        offers = Self.parseOffers(data: d2, currency: currency)
                        status = Self.contextStatus(data: d2) ?? status
                        got200 = true
                        break
                    } else {
                        note = "poll \(path) → HTTP \(c2): \(String((String(data: d2, encoding: .utf8) ?? "").prefix(160)))"
                        if c2 == 429 { break pollRounds }  // quota — stop now
                        // otherwise try the next candidate path
                    }
                }
                if !got200 { break }                       // no path worked this round
                if !offers.isEmpty && status == "complete" { break }
            }
        }

        let head = String((String(data: lastData, encoding: .utf8) ?? "").prefix(450))
        return SearchResult(offers: offers, status: status, httpCode: code,
                            rawHead: head, calls: calls, note: note)
    }

    func searchRoundTrip(origin: String,
                         destination: String,
                         departure: Date,
                         returnDate: Date,
                         adults: Int,
                         nonStop: Bool,
                         currency: String,
                         max: Int = 5) async throws -> [RawOffer] {
        let result = try await performSearch(
            origin: origin, destination: destination,
            departure: departure, returnDate: returnDate,
            adults: adults, currency: currency)
        var offers = result.offers
        if nonStop {
            offers = offers.filter { offer in
                offer.itineraries.allSatisfy { ($0.segments.count - 1) <= 0 }
            }
        }
        // Keep the CHEAPEST offers, not the first few in "best" order.
        offers.sort { $0.price.amount < $1.price.amount }
        return Array(offers.prefix(max))
    }

    /// Fires ONE search (with polling) and returns a human-readable diagnosis.
    func diagnose(origin: String, destination: String,
                  departure: Date, returnDate: Date,
                  adults: Int, currency: String) async throws -> String {
        let r = try await performSearch(
            origin: origin, destination: destination,
            departure: departure, returnDate: returnDate,
            adults: adults, currency: currency)
        if let cheapest = r.offers.map({ $0.price.amount }).min() {
            return "✅ Works! \(origin)→\(destination): \(r.offers.count) offers, cheapest \(Int(cheapest)) \(currency) (status: \(r.status), \(r.calls) calls)."
        }
        let noteLine = r.note.map { "\nPoll error: \($0)" } ?? ""
        return "⚠️ 0 offers after \(r.calls) calls (status: \(r.status)).\(noteLine)\nRaw head:\n\(r.rawHead)"
    }

    // MARK: Defensive JSON -> neutral RawOffer (no strict Codable, tolerates
    // missing / renamed fields so the app never hard-fails on shape drift).

    static func str(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
    static func dbl(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func iso(minutes: Int) -> String { "PT\(minutes / 60)H\(minutes % 60)M" }

    /// Status of the search ("complete"/"incomplete") if present — useful info.
    static func contextStatus(data: Data) -> String? {
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let d = obj?["data"] as? [String: Any]
        let ctx = d?["context"] as? [String: Any]
        return str(ctx?["status"])
    }

    /// The sessionId needed to poll searchIncomplete for the full results.
    static func sessionId(data: Data) -> String? {
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let d = obj?["data"] as? [String: Any]
        let ctx = d?["context"] as? [String: Any]
        return str(ctx?["sessionId"])
    }

    static func parseOffers(data: Data, currency: String) -> [RawOffer] {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let d = obj["data"] as? [String: Any],
            let itins = d["itineraries"] as? [[String: Any]]
        else { return [] }

        return itins.compactMap { it -> RawOffer? in
            let priceObj = it["price"] as? [String: Any]
            guard let amount = dbl(priceObj?["raw"]) else { return nil }
            let legsArr = it["legs"] as? [[String: Any]] ?? []
            let legs: [RawItinerary] = legsArr.map { leg in
                let segsArr = leg["segments"] as? [[String: Any]] ?? []
                let segs: [RawSegment] = segsArr.map { seg in
                    let o = seg["origin"] as? [String: Any]
                    let dst = seg["destination"] as? [String: Any]
                    let mc = seg["marketingCarrier"] as? [String: Any]
                    let oc = seg["operatingCarrier"] as? [String: Any]
                    return RawSegment(
                        departure: RawPoint(iataCode: str(o?["displayCode"]) ?? str(o?["flightPlaceId"]) ?? "",
                                            at: str(seg["departure"]) ?? ""),
                        arrival: RawPoint(iataCode: str(dst?["displayCode"]) ?? str(dst?["flightPlaceId"]) ?? "",
                                          at: str(seg["arrival"]) ?? ""),
                        carrierCode: str(mc?["alternateId"]) ?? str(mc?["name"]) ?? "",
                        operating: RawOperating(carrierCode: str(oc?["alternateId"])),
                        numberOfStops: 0)
                }
                // Prefer real segment count; fall back to stopCount if segments absent.
                let duration = iso(minutes: int(leg["durationInMinutes"]) ?? 0)
                if segs.isEmpty, let stops = int(leg["stopCount"]) {
                    // Fabricate placeholder segments so stop-count traps still work.
                    let placeholders = (0...max(0, stops)).map { _ in
                        RawSegment(departure: RawPoint(iataCode: "", at: ""),
                                   arrival: RawPoint(iataCode: "", at: ""),
                                   carrierCode: "", operating: nil, numberOfStops: 0)
                    }
                    return RawItinerary(duration: duration, segments: placeholders)
                }
                return RawItinerary(duration: duration, segments: segs)
            }
            return RawOffer(price: RawPrice(amount: amount, currency: currency),
                            itineraries: legs,
                            validatingAirlineCodes: nil)
        }
    }
}
