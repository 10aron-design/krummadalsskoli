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
    private var airportCache: [String: (skyId: String, entityId: String)] = [:]

    init(creds: SkyscannerCredentials) { self.creds = creds }

    func update(creds: SkyscannerCredentials) {
        self.creds = creds
        self.airportCache.removeAll()
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

    private func resolveAirport(_ code: String) async throws -> (skyId: String, entityId: String) {
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
        do {
            let decoded = try JSONDecoder().decode(SkyAirportResponse.self, from: data)
            guard let first = decoded.data.first else { throw FlightAPIError.airportNotFound(code) }
            let pair = (skyId: first.skyId, entityId: first.entityId)
            airportCache[code] = pair
            return pair
        } catch let e as FlightAPIError {
            throw e
        } catch {
            throw FlightAPIError.decoding(error.localizedDescription)
        }
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
            path: "/api/v2/flights/searchFlights",
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
        do {
            let decoded = try JSONDecoder().decode(SkyFlightsResponse.self, from: data)
            let itineraries = decoded.data?.itineraries ?? []
            var offers = itineraries.compactMap { Self.mapToRawOffer($0, currency: currency) }
            if nonStop {
                offers = offers.filter { offer in
                    offer.itineraries.allSatisfy { ($0.segments.count - 1) <= 0 }
                }
            }
            return Array(offers.prefix(max))
        } catch {
            throw FlightAPIError.decoding(error.localizedDescription)
        }
    }

    // MARK: Mapping Skyscanner JSON -> neutral RawOffer

    private static func iso(minutes: Int) -> String {
        "PT\(minutes / 60)H\(minutes % 60)M"
    }

    private static func mapToRawOffer(_ itin: SkyItinerary, currency: String) -> RawOffer? {
        guard let price = itin.price?.raw else { return nil }
        let legs: [RawItinerary] = itin.legs.map { leg in
            let segs: [RawSegment] = leg.segments.map { seg in
                RawSegment(
                    departure: RawPoint(iataCode: seg.origin?.displayCode ?? seg.origin?.flightPlaceId ?? "",
                                        at: seg.departure ?? ""),
                    arrival: RawPoint(iataCode: seg.destination?.displayCode ?? seg.destination?.flightPlaceId ?? "",
                                      at: seg.arrival ?? ""),
                    carrierCode: seg.marketingCarrier?.alternateId ?? seg.marketingCarrier?.name ?? "",
                    operating: RawOperating(carrierCode: seg.operatingCarrier?.alternateId),
                    numberOfStops: 0)
            }
            return RawItinerary(duration: iso(minutes: leg.durationInMinutes ?? 0), segments: segs)
        }
        return RawOffer(
            price: RawPrice(amount: price, currency: currency),
            itineraries: legs,
            validatingAirlineCodes: nil)
    }
}

// MARK: - Skyscanner (Sky-Scrapper) JSON shapes (only what we use).

struct SkyAirportResponse: Decodable { let data: [SkyAirport] }
struct SkyAirport: Decodable { let skyId: String; let entityId: String }

struct SkyFlightsResponse: Decodable { let data: SkyData? }
struct SkyData: Decodable { let itineraries: [SkyItinerary]? }

struct SkyItinerary: Decodable {
    let price: SkyPrice?
    let legs: [SkyLeg]
}
struct SkyPrice: Decodable { let raw: Double? }

struct SkyLeg: Decodable {
    let durationInMinutes: Int?
    let stopCount: Int?
    let segments: [SkySegment]
}

struct SkySegment: Decodable {
    let origin: SkyPlace?
    let destination: SkyPlace?
    let departure: String?
    let arrival: String?
    let marketingCarrier: SkyCarrier?
    let operatingCarrier: SkyCarrier?
}

struct SkyPlace: Decodable {
    let flightPlaceId: String?
    let displayCode: String?
}

struct SkyCarrier: Decodable {
    let name: String?
    let alternateId: String?    // usually the 2-letter IATA code
}
