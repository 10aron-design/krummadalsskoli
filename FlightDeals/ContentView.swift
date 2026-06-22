import SwiftUI
import UIKit

// MARK: - Frutiger Aero theme: glossy aqua glass, lush sky→green gradients,
// bubbles and specular shine. Channels mid-2000s "aqua" / Aero glass.

enum Theme {
    static let sky    = Color(red: 0.49, green: 0.83, blue: 1.00)
    static let blue   = Color(red: 0.11, green: 0.52, blue: 0.93)
    static let deep   = Color(red: 0.03, green: 0.24, blue: 0.52)
    static let aqua   = Color(red: 0.20, green: 0.78, blue: 0.92)
    static let leaf   = Color(red: 0.35, green: 0.80, blue: 0.55)

    /// Lush vertical sky → ocean → meadow wash behind everything.
    static let aero = LinearGradient(
        colors: [sky, blue, Color(red: 0.10, green: 0.60, blue: 0.82), leaf],
        startPoint: .top, endPoint: .bottom)

    static let good = Color(red: 0.30, green: 0.78, blue: 0.42)
    static let over = Color(red: 0.98, green: 0.70, blue: 0.18)
    static let trap = Color(red: 0.96, green: 0.50, blue: 0.20)
}

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

// MARK: - Reusable Aero pieces

/// Full-screen lush gradient with floating glossy bubbles / bokeh.
struct AeroBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Theme.aero
                bubble(180, .white).position(x: w * 0.18, y: h * 0.10).opacity(0.5)
                bubble(120, .white).position(x: w * 0.85, y: h * 0.16).opacity(0.45)
                bubble(90,  .white).position(x: w * 0.70, y: h * 0.05).opacity(0.4)
                bubble(220, Theme.leaf).position(x: w * 0.10, y: h * 0.92).opacity(0.45)
                bubble(160, Theme.aqua).position(x: w * 0.92, y: h * 0.80).opacity(0.4)
                bubble(70,  .white).position(x: w * 0.40, y: h * 0.45).opacity(0.35)
            }
        }
        .ignoresSafeArea()
    }

    private func bubble(_ d: CGFloat, _ tint: Color) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [tint.opacity(0.9), tint.opacity(0.0)],
                center: .topLeading, startRadius: 1, endRadius: d))
            .frame(width: d, height: d)
            .blur(radius: 3)
    }
}

/// Glossy glass surface: frosted material, top sheen, bright rim, soft shadow.
struct GlassCard: ViewModifier {
    var corner: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.85), .white.opacity(0.18)],
                            startPoint: .top, endPoint: .bottom))
                    // Specular sheen across the top third.
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.75), .clear],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [.white.opacity(0.95), .white.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .shadow(color: Theme.deep.opacity(0.25), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassCard(corner: CGFloat = 22) -> some View {
        modifier(GlassCard(corner: corner))
    }
}

/// Glossy "aqua" pill button for stats — vibrant fill + top shine.
struct AeroPill: View {
    let systemImage: String
    let text: String
    var tint: Color = Theme.blue

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .shadow(color: tint.opacity(0.6), radius: 0.5, y: 0.5)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            ZStack {
                Capsule().fill(LinearGradient(
                    colors: [tint.opacity(0.95), tint],
                    startPoint: .top, endPoint: .bottom))
                Capsule().fill(LinearGradient(
                    colors: [.white.opacity(0.85), .clear],
                    startPoint: .top, endPoint: .center))
                    .padding(1.5)
            }
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 0.6))
        .shadow(color: tint.opacity(0.4), radius: 2, y: 1)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    init() {
        // Glassy, translucent nav/tab bars so the gradient glows through.
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().standardAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().standardAppearance = tab
    }

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
                BrandHeader(goodCount: store.goodDeals.count, lastScan: store.lastScanDate)
                    .aeroRow()

                if store.isScanning || store.lastScanDate != nil || store.lastError != nil {
                    statusCard.aeroRow()
                }

                if !store.goodDeals.isEmpty {
                    SectionHeader("Good deals", icon: "checkmark.seal.fill", tint: Theme.good).aeroRow(0)
                    ForEach(store.goodDeals) {
                        DealRow(deal: $0, adults: store.config.adults, category: .good).aeroRow()
                    }
                }
                if !store.aboveBudgetDeals.isEmpty {
                    SectionHeader("Above your max price", icon: "tag.fill", tint: Theme.over).aeroRow(0)
                    ForEach(store.aboveBudgetDeals) {
                        DealRow(deal: $0, adults: store.config.adults, category: .over).aeroRow()
                    }
                }
                if !store.trapDeals.isEmpty {
                    SectionHeader("Skipped — looks like a trap", icon: "exclamationmark.triangle.fill", tint: Theme.trap).aeroRow(0)
                    ForEach(store.trapDeals) {
                        DealRow(deal: $0, adults: store.config.adults, category: .trap).aeroRow()
                    }
                }
                if store.deals.isEmpty && !store.isScanning {
                    EmptyState().aeroRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AeroBackground())
            .navigationTitle("Iceland → Japan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.runScan() }
                    } label: {
                        if store.isScanning { ProgressView() }
                        else {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(
                                    Circle().fill(LinearGradient(
                                        colors: [Theme.aqua, Theme.blue],
                                        startPoint: .top, endPoint: .bottom)))
                                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                                .shadow(color: Theme.deep.opacity(0.4), radius: 3, y: 2)
                        }
                    }
                    .disabled(store.isScanning)
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .font(.caption).foregroundStyle(Theme.deep)
            }
            if let e = store.lastError {
                Label(e, systemImage: "exclamationmark.bubble.fill")
                    .font(.caption).foregroundStyle(Theme.trap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(corner: 18)
    }
}

/// Row styling helper: clears default list chrome so cards float on the gradient.
extension View {
    func aeroRow(_ vPad: CGFloat = 6) -> some View {
        self
            .listRowInsets(EdgeInsets(top: vPad, leading: 16, bottom: vPad, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Glossy aqua hero panel echoing the app icon.
struct BrandHeader: View {
    let goodCount: Int
    let lastScan: Date?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Vibrant aqua glass body.
            LinearGradient(colors: [Theme.aqua, Theme.blue, Theme.deep],
                           startPoint: .top, endPoint: .bottom)
            // Big top reflection sheen.
            LinearGradient(colors: [.white.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .center)
            // Decorative bokeh + plane like the icon.
            Circle().fill(.white.opacity(0.25)).frame(width: 90).blur(radius: 6)
                .offset(x: 120, y: -40)
            Image(systemName: "airplane")
                .font(.system(size: 88, weight: .black))
                .rotationEffect(.degrees(-18))
                .foregroundStyle(.white.opacity(0.22))
                .offset(x: 140, y: -10)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "airplane.departure")
                    Text("KEF → TYO · OSA").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white.opacity(0.9))

                Text(goodCount > 0 ? "\(goodCount) good deal\(goodCount == 1 ? "" : "s") found"
                                   : "Hunting cheap round-trips")
                    .font(.title.weight(.heavy))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.deep.opacity(0.5), radius: 2, y: 1)

                Text(lastScan == nil ? "Tap ↻ to scan flexible dates"
                                     : "Updated \(lastScan!.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(18)
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: Theme.deep.opacity(0.35), radius: 12, y: 6)
        .padding(.top, 6)
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
        Label(title.uppercased(), systemImage: icon)
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .shadow(color: Theme.deep.opacity(0.6), radius: 1, y: 1)
            .padding(.top, 8)
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(colors: [Theme.aqua, Theme.blue],
                                                startPoint: .top, endPoint: .bottom))
            Text("No flights yet").font(.headline).foregroundStyle(Theme.deep)
            Text("Add your RapidAPI key in Settings, then tap ↻ to scan.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 16)
        .glassCard()
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
                // Glossy category capsule on the leading edge.
                Capsule()
                    .fill(LinearGradient(colors: [category.color.opacity(0.9), category.color],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(deal.price)) \(deal.currency)")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(category == .trap ? Color.secondary : Theme.deep)
                        if adults > 1 {
                            Text("· \(Int(deal.price) / adults)/person")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(deal.origin) → \(deal.destination)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.blue)
                    }

                    Text(deal.departureDate.prettyDate
                         + (deal.nights.map { " · \($0) nights" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        AeroPill(systemImage: "arrow.triangle.swap",
                                 text: "\(deal.stopsOutbound)/\(deal.stopsInbound) stops",
                                 tint: Theme.blue)
                        AeroPill(systemImage: "clock.fill",
                                 text: String(format: "%.0fh", deal.totalTravelHours),
                                 tint: Theme.aqua)
                        if !deal.airlines.isEmpty {
                            AeroPill(systemImage: "building.2.fill",
                                     text: deal.airlines.prefix(2).joined(separator: ","),
                                     tint: Theme.leaf)
                        }
                    }

                    if deal.isTrap {
                        Text(deal.trapReasons.map { $0.rawValue }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(Theme.trap)
                    }
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

struct DealDetailView: View {
    let deal: FlightDeal
    var adults: Int = 1

    var body: some View {
        List {
            priceHeader.aeroRow()

            glassSection("Route") {
                infoRow("From", deal.origin)
                infoRow("To", deal.destination)
                infoRow("Depart", deal.departureDate.prettyDate)
                if let r = deal.returnDate { infoRow("Return", r.prettyDate) }
                if let n = deal.nights { infoRow("Trip length", "\(n) nights") }
            }
            glassSection("Journey") {
                infoRow("Stops (out/in)", "\(deal.stopsOutbound)/\(deal.stopsInbound)")
                infoRow("Longest leg", String(format: "%.1f h", deal.totalTravelHours))
                infoRow("Longest layover", String(format: "%.1f h", deal.longestLayoverHours))
                infoRow("Airlines", deal.airlines.joined(separator: ", "))
            }
            if deal.isTrap {
                glassSection("Why we flagged it") {
                    ForEach(deal.trapReasons, id: \.self) { r in
                        Label(r.rawValue, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.trap)
                    }
                }
            }
            glassSection("Book it") {
                Text(deal.deepLinkInfo).font(.callout).foregroundStyle(Theme.deep)
                if let url = bookingURL {
                    Link(destination: url) {
                        Label("Open Google Flights", systemImage: "arrow.up.right.square.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AeroBackground())
        .navigationTitle(deal.isTrap ? "Trap deal" : "Good deal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func glassSection<Content: View>(_ title: String,
                                             @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.blue)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
        .aeroRow()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(Theme.deep).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var priceHeader: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: deal.isTrap ? [Theme.trap, Color(red: 0.78, green: 0.30, blue: 0.10)]
                                    : [Theme.aqua, Theme.blue, Theme.deep],
                startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.white.opacity(0.55), .clear],
                           startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Int(deal.price)) \(deal.currency)")
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.deep.opacity(0.5), radius: 2, y: 1)
                Text(adults > 1
                     ? "Total for \(adults) adults · \(Int(deal.price) / adults) \(deal.currency) per person"
                     : "Total for 1 adult")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Text("\(deal.origin) → \(deal.destination) · \(deal.departureDate.prettyDate)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: Theme.deep.opacity(0.35), radius: 12, y: 6)
        .padding(.top, 6)
    }

    private var bookingURL: URL? {
        let dep = deal.departureDate.ymd
        let ret = deal.returnDate?.ymd ?? ""
        let q = "Flights from \(deal.origin) to \(deal.destination) on \(dep) returning \(ret)"
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/travel/flights?q=\(enc)")
    }
}
