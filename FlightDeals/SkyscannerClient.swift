import Foundation

/// Credentials for the Skyscanner data feed via RapidAPI.
/// Sign up free at https://rapidapi.com, subscribe to the **"Sky-Scrapper"**
/// API, then copy your X-RapidAPI-Key here. No OAuth, no approval wait.
struct SkyscannerCredentials: Codable, Equatable {
    var rapidApiKey: String = ""
    /// The RapidAPI host for the Sky-Scrapper listing. Override only if you
    /// subscribed to a differently-named Skyscanner listing on RapidAPI.
    var rapidApiHost: String = "sky-scrapper.p.rapidapi.com"
    /// Market/locale knobs Skyscanner expects.
    var market: String = "US"
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

    init(creds: SkyscannerCredentials) {
        self.creds = creds
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([String: AirportID].self, from: data) {
            self.airportCache = cached
        } else {
            self.airportCache = [:]
        }
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

    func searchRoundTrip(origin: String,
                         destination: String,
                         departure: Date,
                         returnDate: Date,
                         adults: Int,
                         nonStop: Bool,
                         currency: String,
                         max: Int = 5) async throws -> [RawOffer] {
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

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw FlightAPIError.http(0, "no response") }
        guard http.statusCode == 200 else {
            throw FlightAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        var offers = Self.parseOffers(data: data, currency: currency)
        if nonStop {
            offers = offers.filter { offer in
                offer.itineraries.allSatisfy { ($0.segments.count - 1) <= 0 }
            }
        }
        return Array(offers.prefix(max))
    }

    /// Fires ONE search and returns a human-readable diagnosis: HTTP code,
    /// resolved airport ids, search status, offers parsed, and — if nothing
    /// parsed — a snippet of the raw JSON so the shape can be inspected.
    func diagnose(origin: String, destination: String,
                  departure: Date, returnDate: Date,
                  adults: Int, currency: String) async throws -> String {
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
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            return "❌ HTTP \(code): \(String(body.prefix(200)))"
        }
        let offers = Self.parseOffers(data: data, currency: currency)
        let status = Self.contextStatus(data: data) ?? "unknown"
        if let cheapest = offers.map({ $0.price.amount }).min() {
            return "✅ Works! \(origin)→\(destination): \(offers.count) offers, cheapest \(Int(cheapest)) \(currency) (status: \(status))."
        }
        let body = String(data: data, encoding: .utf8) ?? "<non-text>"
        return "⚠️ HTTP 200 but 0 offers parsed (status: \(status)). Raw head:\n\(String(body.prefix(500)))"
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
