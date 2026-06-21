import Foundation

/// Where the API keys live. Filled from Settings and kept in UserDefaults.
/// Get free keys at https://developers.amadeus.com (Self-Service apps).
struct AmadeusCredentials: Codable, Equatable {
    var clientId: String = ""
    var clientSecret: String = ""
    /// Use the test host while playing, switch to production for real prices.
    var useProduction: Bool = false

    var host: String { useProduction ? "api.amadeus.com" : "test.api.amadeus.com" }
    var isConfigured: Bool { !clientId.isEmpty && !clientSecret.isEmpty }
}

enum AmadeusError: LocalizedError {
    case notConfigured
    case auth(String)
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your Amadeus API key in Settings first."
        case .auth(let m):   return "Auth failed: \(m)"
        case .http(let c, let m): return "API error \(c): \(m)"
        case .decoding(let m):    return "Could not read API response: \(m)"
        }
    }
}

/// Thin async wrapper around the two Amadeus endpoints we need:
/// OAuth token + Flight Offers Search.
actor AmadeusClient {
    private var creds: AmadeusCredentials
    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    init(creds: AmadeusCredentials) {
        self.creds = creds
    }

    func update(creds: AmadeusCredentials) {
        self.creds = creds
        self.cachedToken = nil
        self.tokenExpiry = .distantPast
    }

    // MARK: Token

    private func token() async throws -> String {
        guard creds.isConfigured else { throw AmadeusError.notConfigured }
        if let t = cachedToken, tokenExpiry > Date().addingTimeInterval(60) { return t }

        let url = URL(string: "https://\(creds.host)/v1/security/oauth2/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=client_credentials&client_id=\(creds.clientId)&client_secret=\(creds.clientSecret)"
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AmadeusError.auth("no response") }
        guard http.statusCode == 200 else {
            throw AmadeusError.auth(String(data: data, encoding: .utf8) ?? "status \(http.statusCode)")
        }
        struct TokenResp: Decodable { let access_token: String; let expires_in: Double }
        do {
            let tr = try JSONDecoder().decode(TokenResp.self, from: data)
            cachedToken = tr.access_token
            tokenExpiry = Date().addingTimeInterval(tr.expires_in)
            return tr.access_token
        } catch {
            throw AmadeusError.decoding(error.localizedDescription)
        }
    }

    // MARK: Flight Offers Search

    /// One round-trip search for a concrete origin/destination/date pair.
    func searchRoundTrip(origin: String,
                         destination: String,
                         departure: Date,
                         returnDate: Date,
                         adults: Int,
                         nonStop: Bool,
                         currency: String,
                         max: Int = 5) async throws -> [RawOffer] {
        let tok = try await token()
        var comps = URLComponents(string: "https://\(creds.host)/v2/shopping/flight-offers")!
        comps.queryItems = [
            .init(name: "originLocationCode", value: origin),
            .init(name: "destinationLocationCode", value: destination),
            .init(name: "departureDate", value: departure.ymd),
            .init(name: "returnDate", value: returnDate.ymd),
            .init(name: "adults", value: String(adults)),
            .init(name: "currencyCode", value: currency),
            .init(name: "nonStop", value: nonStop ? "true" : "false"),
            .init(name: "max", value: String(max))
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AmadeusError.http(0, "no response") }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AmadeusError.http(http.statusCode, msg)
        }
        do {
            return try JSONDecoder().decode(FlightOffersResponse.self, from: data).data
        } catch {
            throw AmadeusError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Raw Amadeus JSON (only the fields we use).

struct FlightOffersResponse: Decodable { let data: [RawOffer] }

struct RawOffer: Decodable {
    let id: String
    let price: RawPrice
    let itineraries: [RawItinerary]
    let validatingAirlineCodes: [String]?
}

struct RawPrice: Decodable {
    let grandTotal: String?
    let total: String?
    let currency: String?
    var amount: Double { Double(grandTotal ?? total ?? "0") ?? 0 }
}

struct RawItinerary: Decodable {
    let duration: String       // ISO-8601 like "PT14H30M"
    let segments: [RawSegment]
}

struct RawSegment: Decodable {
    let departure: RawPoint
    let arrival: RawPoint
    let carrierCode: String
    let operating: RawOperating?
    let numberOfStops: Int?
}

struct RawOperating: Decodable { let carrierCode: String? }

struct RawPoint: Decodable {
    let iataCode: String
    let at: String             // "2026-08-12T16:40:00"
}
