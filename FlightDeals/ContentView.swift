import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            DealsView()
                .tabItem { Label("Deals", systemImage: "airplane") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
    }
}

struct DealsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if !store.goodDeals.isEmpty {
                    Section("Good deals 🎉") {
                        ForEach(store.goodDeals) { DealRow(deal: $0) }
                    }
                }
                if !store.trapDeals.isEmpty {
                    Section("Skipped — looks like a trap ⚠️") {
                        ForEach(store.trapDeals) { DealRow(deal: $0) }
                    }
                }
                if store.deals.isEmpty && !store.isScanning {
                    Text("No flights yet. Add your API key in Settings, then tap Scan.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Iceland → Japan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.runScan() }
                    } label: {
                        if store.isScanning { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(store.isScanning)
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            if store.isScanning {
                HStack {
                    ProgressView()
                    VStack(alignment: .leading) {
                        Text("Scanning flexible dates…").font(.subheadline)
                        Text(store.progressText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let d = store.lastScanDate {
                Label("Last scan: \(d.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let e = store.lastError {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct DealRow: View {
    let deal: FlightDeal

    var body: some View {
        NavigationLink {
            DealDetailView(deal: deal)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Int(deal.price)) \(deal.currency)")
                        .font(.headline)
                        .foregroundStyle(deal.isTrap ? .secondary : .primary)
                    Spacer()
                    Text("\(deal.origin) → \(deal.destination)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("\(deal.departureDate.prettyDate)"
                     + (deal.nights.map { " · \($0)n" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label("\(deal.stopsOutbound)/\(deal.stopsInbound) stops", systemImage: "arrow.triangle.swap")
                    Label(String(format: "%.0fh", deal.totalTravelHours), systemImage: "clock")
                }
                .font(.caption2).foregroundStyle(.secondary)
                if deal.isTrap {
                    Text(deal.trapReasons.map { $0.rawValue }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct DealDetailView: View {
    let deal: FlightDeal

    var body: some View {
        List {
            Section("Price") {
                Text("\(Int(deal.price)) \(deal.currency)").font(.largeTitle.bold())
            }
            Section("Route") {
                LabeledContent("From", value: deal.origin)
                LabeledContent("To", value: deal.destination)
                LabeledContent("Depart", value: deal.departureDate.prettyDate)
                if let r = deal.returnDate { LabeledContent("Return", value: r.prettyDate) }
                if let n = deal.nights { LabeledContent("Trip length", value: "\(n) nights") }
            }
            Section("Journey") {
                LabeledContent("Stops (out/in)", value: "\(deal.stopsOutbound)/\(deal.stopsInbound)")
                LabeledContent("Longest leg", value: String(format: "%.1f h", deal.totalTravelHours))
                LabeledContent("Longest layover", value: String(format: "%.1f h", deal.longestLayoverHours))
                LabeledContent("Airlines", value: deal.airlines.joined(separator: ", "))
            }
            if deal.isTrap {
                Section("Why we flagged it ⚠️") {
                    ForEach(deal.trapReasons, id: \.self) { r in
                        Label(r.rawValue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("Book it") {
                Text(deal.deepLinkInfo).font(.callout)
                if let url = bookingURL {
                    Link("Open Google Flights", destination: url)
                }
            }
        }
        .navigationTitle(deal.isTrap ? "Trap deal" : "Good deal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bookingURL: URL? {
        let dep = deal.departureDate.ymd
        let ret = deal.returnDate?.ymd ?? ""
        let q = "Flights from \(deal.origin) to \(deal.destination) on \(dep) returning \(ret)"
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/travel/flights?q=\(enc)")
    }
}
