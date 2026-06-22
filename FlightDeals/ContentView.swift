import SwiftUI

// MARK: - Brand theme (matches the app icon: deep navy → sky blue).

enum Theme {
    static let navy = Color(red: 0.031, green: 0.110, blue: 0.227)   // #081C3A
    static let blue = Color(red: 0.000, green: 0.450, blue: 0.900)   // accent
    static let sky  = Color(red: 0.45,  green: 0.74,  blue: 1.00)

    static let brand = LinearGradient(
        colors: [navy, blue],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let good = Color.green
    static let over = Color(red: 0.92, green: 0.60, blue: 0.10)
    static let trap = Color.orange
}

/// What bucket a deal falls in — drives its accent colour.
enum DealCategory {
    case good, over, trap
    var color: Color {
        switch self {
        case .good: return Theme.good
        case .over: return Theme.over
        case .trap: return Theme.trap
        }
    }
}

/// Small pill used for stops / duration / airlines.
struct Chip: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            DealsView()
                .tabItem { Label("Deals", systemImage: "airplane.departure") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.blue)
    }
}

struct DealsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                BrandHeader(
                    goodCount: store.goodDeals.count,
                    lastScan: store.lastScanDate)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                statusSection

                if !store.goodDeals.isEmpty {
                    Section {
                        ForEach(store.goodDeals) {
                            DealRow(deal: $0, adults: store.config.adults, category: .good)
                        }
                    } header: { SectionHeader("Good deals", icon: "checkmark.seal.fill", tint: Theme.good) }
                }
                if !store.aboveBudgetDeals.isEmpty {
                    Section {
                        ForEach(store.aboveBudgetDeals) {
                            DealRow(deal: $0, adults: store.config.adults, category: .over)
                        }
                    } header: { SectionHeader("Above your max price", icon: "tag.fill", tint: Theme.over) }
                }
                if !store.trapDeals.isEmpty {
                    Section {
                        ForEach(store.trapDeals) {
                            DealRow(deal: $0, adults: store.config.adults, category: .trap)
                        }
                    } header: { SectionHeader("Skipped — looks like a trap", icon: "exclamationmark.triangle.fill", tint: Theme.trap) }
                }
                if store.deals.isEmpty && !store.isScanning {
                    EmptyState()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Iceland → Japan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.runScan() }
                    } label: {
                        if store.isScanning { ProgressView() }
                        else { Image(systemName: "arrow.clockwise.circle.fill").imageScale(.large) }
                    }
                    .disabled(store.isScanning)
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            if store.isScanning {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scanning flexible dates…").font(.subheadline.weight(.semibold))
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
                    .font(.caption).foregroundStyle(Theme.over)
            }
        }
    }
}

/// Full-bleed gradient hero at the top of the deals list.
struct BrandHeader: View {
    let goodCount: Int
    let lastScan: Date?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.brand
            // Decorative plane mirroring the app icon.
            Image(systemName: "airplane")
                .font(.system(size: 92, weight: .black))
                .rotationEffect(.degrees(-18))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 150, y: -18)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "airplane.departure")
                    Text("KEF → TYO · OSA").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))

                Text(goodCount > 0 ? "\(goodCount) good deal\(goodCount == 1 ? "" : "s") found"
                                   : "Hunting cheap round-trips")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(lastScan == nil ? "Tap ↻ to scan flexible dates"
                                     : "Updated \(lastScan!.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(18)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.vertical, 4)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let tint: Color
    init(_ title: String, icon: String, tint: Color) {
        self.title = title; self.icon = icon; self.tint = tint
    }
    var body: some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.blue)
            Text("No flights yet")
                .font(.headline)
            Text("Add your RapidAPI key in Settings, then tap ↻ to scan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct DealRow: View {
    let deal: FlightDeal
    var adults: Int = 1
    var category: DealCategory = .good

    var body: some View {
        NavigationLink {
            DealDetailView(deal: deal, adults: adults)
        } label: {
            HStack(spacing: 12) {
                // Accent stripe by category.
                RoundedRectangle(cornerRadius: 3)
                    .fill(category.color)
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(deal.price)) \(deal.currency)")
                            .font(.title3.bold())
                            .foregroundStyle(category == .trap ? .secondary : .primary)
                        if adults > 1 {
                            Text("· \(Int(deal.price) / adults)/person")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(deal.origin) → \(deal.destination)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.blue)
                    }

                    Text(deal.departureDate.prettyDate
                         + (deal.nights.map { " · \($0) nights" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Chip(systemImage: "arrow.triangle.swap",
                             text: "\(deal.stopsOutbound)/\(deal.stopsInbound) stops",
                             tint: Theme.blue)
                        Chip(systemImage: "clock",
                             text: String(format: "%.0fh", deal.totalTravelHours),
                             tint: .secondary)
                        if !deal.airlines.isEmpty {
                            Chip(systemImage: "building.2",
                                 text: deal.airlines.prefix(2).joined(separator: ","),
                                 tint: .secondary)
                        }
                    }

                    if deal.isTrap {
                        Text(deal.trapReasons.map { $0.rawValue }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(Theme.trap)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct DealDetailView: View {
    let deal: FlightDeal
    var adults: Int = 1

    var body: some View {
        List {
            Section {
                priceHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                Section {
                    ForEach(deal.trapReasons, id: \.self) { r in
                        Label(r.rawValue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.trap)
                    }
                } header: { SectionHeader("Why we flagged it", icon: "exclamationmark.triangle.fill", tint: Theme.trap) }
            }
            Section("Book it") {
                Text(deal.deepLinkInfo).font(.callout)
                if let url = bookingURL {
                    Link(destination: url) {
                        Label("Open Google Flights", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle(deal.isTrap ? "Trap deal" : "Good deal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var priceHeader: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(deal.isTrap ? AnyShapeStyle(Theme.trap.gradient)
                                  : AnyShapeStyle(Theme.brand))
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Int(deal.price)) \(deal.currency)")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white)
                Text(adults > 1
                     ? "Total for \(adults) adults · \(Int(deal.price) / adults) \(deal.currency) per person"
                     : "Total for 1 adult")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(deal.origin) → \(deal.destination) · \(deal.departureDate.prettyDate)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.vertical, 6)
    }

    private var bookingURL: URL? {
        let dep = deal.departureDate.ymd
        let ret = deal.returnDate?.ymd ?? ""
        let q = "Flights from \(deal.origin) to \(deal.destination) on \(dep) returning \(ret)"
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/travel/flights?q=\(enc)")
    }
}
