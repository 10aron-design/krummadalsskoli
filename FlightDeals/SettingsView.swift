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
            TextField("Amadeus Client ID", text: $store.creds.clientId)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Amadeus Client Secret", text: $store.creds.clientSecret)
            Toggle("Use production prices", isOn: $store.creds.useProduction)
        } header: {
            Text("API key")
        } footer: {
            Text("Free keys at developers.amadeus.com → create a Self-Service app. Test mode has limited routes; flip to production for real fares.")
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
        } header: {
            Text("Flexible dates")
        } footer: {
            Text("We scan every Nth day between the two months and try a few trip lengths. Smaller steps = more thorough but more API calls.")
        }
    }

    private var dealSection: some View {
        Section("What counts as a good deal") {
            HStack {
                Text("Max price")
                Spacer()
                TextField("price", value: $store.config.maxPrice, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(store.config.preferredCurrency)
            }
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
        Section("About") {
            Button {
                Task { await store.runScan() }
            } label: {
                Label("Run scan now", systemImage: "magnifyingglass")
            }
            .disabled(store.isScanning)
            Text("Background scan runs ~once a day when iOS allows. Keep notifications enabled.")
                .font(.caption).foregroundStyle(.secondary)
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
