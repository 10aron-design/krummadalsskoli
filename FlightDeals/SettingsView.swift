import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                routeSection
                flexibleDatesSection
                dealSection
                trapSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    private var apiSection: some View {
        Section {
            SecureField("X-RapidAPI-Key", text: $store.creds.rapidApiKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("RapidAPI host", text: $store.creds.rapidApiHost)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Market", text: $store.creds.market)
                .textInputAutocapitalization(.characters)
        } header: {
            Text("Skyscanner API key")
        } footer: {
            Text("Get a free key at rapidapi.com → subscribe to the \"Sky-Scrapper\" API → copy your X-RapidAPI-Key. Keep the host as sky-scrapper.p.rapidapi.com unless you picked a different Skyscanner listing.")
        }
    }

    private var routeSection: some View {
        Section("Route") {
            CodeEditor(title: "From (IATA)", codes: $store.config.originCodes)
            CodeEditor(title: "To (IATA)", codes: $store.config.destinationCodes)
            Stepper("Adults: \(store.config.adults)", value: $store.config.adults, in: 1...9)
            Toggle("Non-stop only", isOn: $store.config.nonStopOnly)
            TextField("Currency", text: $store.config.preferredCurrency)
                .textInputAutocapitalization(.characters)
        }
    }

    private var flexibleDatesSection: some View {
        Section {
            DatePicker("Earliest month",
                       selection: $store.config.earliestDeparture,
                       displayedComponents: .date)
            DatePicker("Latest month",
                       selection: $store.config.latestDeparture,
                       displayedComponents: .date)
            Stepper("Min trip: \(store.config.minTripNights) nights",
                    value: $store.config.minTripNights, in: 1...60)
            Stepper("Max trip: \(store.config.maxTripNights) nights",
                    value: $store.config.maxTripNights, in: 1...90)
            Stepper("Sample every \(store.config.samplingStepDays) days",
                    value: $store.config.samplingStepDays, in: 1...14)
            Stepper("Max searches per scan: \(store.config.maxRequestsPerScan)",
                    value: $store.config.maxRequestsPerScan, in: 1...50)
        } header: {
            Text("Flexible dates")
        } footer: {
            Text("We scan every Nth day between the two months and try a few trip lengths, spread evenly to fit the budget. ⚠️ Each search costs ~2–5 RapidAPI calls (Skyscanner returns results in stages, so the app polls). Free plans cap you near ~100 calls/MONTH — keep \"Max searches per scan\" low (e.g. 5) and scan sparingly.")
        }
    }

    private var dealSection: some View {
        Section {
            HStack {
                Text("Max price (total)")
                Spacer()
                TextField("price", value: $store.config.maxPrice, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(store.config.preferredCurrency)
            }
            if store.config.adults > 1 {
                Text("= \(Int(store.config.maxPrice) / store.config.adults) \(store.config.preferredCurrency) per person × \(store.config.adults) adults")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("What counts as a good deal")
        } footer: {
            Text("Max price is the TOTAL for everyone in the search (\(store.config.adults) adult\(store.config.adults == 1 ? "" : "s")). Iceland→Japan round-trips are rarely under ~600 \(store.config.preferredCurrency) per person, so set this realistically or you'll see nothing in \"Good deals\".")
        }
    }

    private var trapSection: some View {
        Section {
            Stepper("Max layover: \(Int(store.config.maxLayoverHours))h",
                    value: $store.config.maxLayoverHours, in: 1...24, step: 1)
            Stepper("Max total travel: \(Int(store.config.maxTotalTravelHours))h",
                    value: $store.config.maxTotalTravelHours, in: 10...60, step: 1)
            Stepper("Max stops per leg: \(store.config.maxStopsPerLeg)",
                    value: $store.config.maxStopsPerLeg, in: 0...4)
            Toggle("Reject self-transfer / mixed airlines", isOn: $store.config.rejectSelfTransfer)
            Toggle("Reject overnight layovers", isOn: $store.config.rejectOvernightLayover)
        } header: {
            Text("Trap filter 🪤")
        } footer: {
            Text("Cheap fares that hide 52-hour journeys, unconnected airlines, or overnight airport sleepovers get flagged and won't trigger a notification.")
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                Task { await store.testAPI() }
            } label: {
                Label("Test API (1 call)", systemImage: "checkmark.seal")
            }
            .disabled(store.isScanning)
            Button {
                Task { await store.runScan() }
            } label: {
                Label("Run full scan now", systemImage: "magnifyingglass")
            }
            .disabled(store.isScanning)
            if let msg = store.lastError {
                Text(msg).font(.caption)
                    .foregroundStyle(msg.hasPrefix("✅") ? .green : .orange)
                    .textSelection(.enabled)   // long-press to copy & share with support
            }
        } header: {
            Text("About")
        } footer: {
            Text("Tap \"Test API\" first — it spends only ~1 request to confirm your key works before you run a full scan. Background scan runs ~once a day when iOS allows; keep notifications enabled.")
        }
    }
}

/// Edits a comma-friendly list of IATA codes.
struct CodeEditor: View {
    let title: String
    @Binding var codes: [String]

    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("e.g. KEF", text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onAppear { text = codes.joined(separator: ", ") }
                .onChange(of: text) { new in
                    codes = new
                        .split(whereSeparator: { $0 == "," || $0 == " " })
                        .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                        .filter { !$0.isEmpty }
                }
        }
    }
}
