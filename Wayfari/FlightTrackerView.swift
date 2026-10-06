import SwiftUI

enum TrackerTab: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case flightNumber = "Flight number"
    case route = "Route"
    var id: String { rawValue }
}

enum TrackerDirection: String, CaseIterable, Identifiable {
    case departures = "Departures"
    case arrivals = "Arrivals"
    var id: String { rawValue }
}

enum LiveFlightStatus: String {
    case onTime = "On time"
    case delayed = "Delayed"
    case boarding = "Boarding"
    case departed = "Departed"

    var color: Color {
        switch self {
        case .onTime, .departed: return Color(hex: "34A853")
        case .delayed: return .orange
        case .boarding: return Theme.accent
        }
    }
}

struct TrackedFlight: Identifiable {
    let id = UUID()
    let time: String
    let airportCode: String
    let status: LiveFlightStatus
    let airlineCode: String
    let flightNumber: String
}

enum AirportScheduleService {
    private static let carriers: [(code: String, prefix: String)] = [
        ("PK", "PA"), ("SV", "SV"), ("J2", "J2"), ("AA", "AA"), ("AS", "AS"),
        ("B6", "B6"), ("BA", "BA"), ("IB", "IB"), ("QR", "QR"), ("VA", "VA"),
        ("WY", "WY"), ("AC", "AC"), ("EK", "EK"), ("FZ", "FZ"), ("G9", "G9"),
        ("TK", "TK"), ("QR", "QR"),
    ]

    static func flights(
        airport: Airport,
        direction: TrackerDirection,
        seed: Int = 0
    ) -> [TrackedFlight] {
        let destinations = AirportCatalog.all.filter { $0.code != airport.code }
        guard !destinations.isEmpty else { return [] }

        let safeSeed = abs(seed)
        let times: [(Int, Int)] = [
            (2, 15), (2, 15), (3, 10), (3, 10), (3, 10), (3, 10),
            (4, 30), (5, 0), (5, 45), (6, 20), (7, 10), (8, 0),
            (9, 30), (11, 15), (13, 40), (15, 20), (17, 55), (19, 10),
        ]
        let statuses: [LiveFlightStatus] = [.onTime, .onTime, .onTime, .onTime, .onTime,
                                            .onTime, .boarding, .onTime, .delayed, .onTime,
                                            .onTime, .departed, .onTime, .onTime, .onTime,
                                            .onTime, .onTime, .onTime]

        return times.enumerated().map { index, slot in
            let dest = destinations[positiveMod(safeSeed + index, destinations.count)]
            let carrier = carriers[positiveMod(safeSeed + index * 3, carriers.count)]
            let hour = slot.0
            let minute = slot.1
            let period = hour >= 12 ? "PM" : "AM"
            let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            let timeStr = String(format: "%d:%02d %@", h12, minute, period)
            let code = direction == .departures ? dest.code : airport.code
            let flightNum = carrier.prefix + " \(100 + positiveMod(safeSeed + index, 900) * 7 % 900)"
            return TrackedFlight(
                time: timeStr,
                airportCode: code,
                status: statuses[positiveMod(index, statuses.count)],
                airlineCode: carrier.code == "J2" ? "J2" : carrier.code,
                flightNumber: flightNum
            )
        }
    }

    private static func positiveMod(_ value: Int, _ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let mod = value % count
        return mod >= 0 ? mod : mod + count
    }
}

struct FlightTrackerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: TrackerTab = .schedule
    @State private var direction: TrackerDirection = .departures
    @State private var airport: Airport
    @State private var flightNumberQuery = ""
    @State private var routeFrom: Airport
    @State private var routeTo: Airport
    @State private var showAirportPicker = false

    init(defaultAirport: Airport? = nil) {
        let base = defaultAirport
            ?? AirportCatalog.all.first { $0.code == "LHE" }
            ?? AirportCatalog.all.first!
        _airport = State(initialValue: base)
        _routeFrom = State(initialValue: base)
        _routeTo = State(initialValue: AirportCatalog.all.first { $0.code == "DXB" } ?? AirportCatalog.all.first!)
    }

    private var scheduleFlights: [TrackedFlight] {
        AirportScheduleService.flights(airport: airport, direction: direction, seed: airport.code.hashValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                Divider()
                tabContent
            }
            .background(Theme.background)
            .navigationTitle("Track a Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.sublabel)
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray5), in: Circle())
                    }
                }
            }
            .sheet(isPresented: $showAirportPicker) {
                AirportPickerSheet(
                    title: "Select airport",
                    selected: airport
                ) { selected in
                    airport = selected
                    routeFrom = selected
                }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TrackerTab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 6) {
                        Text(t.rawValue)
                            .font(.system(size: 14, weight: tab == t ? .semibold : .regular))
                            .foregroundColor(tab == t ? Theme.label : Theme.sublabel)
                        Rectangle()
                            .fill(tab == t ? Theme.label : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .schedule: scheduleTab
        case .flightNumber: flightNumberTab
        case .route: routeTab
        }
    }

    private var scheduleTab: some View {
        VStack(spacing: 0) {
            Button { showAirportPicker = true } label: {
                HStack(spacing: 8) {
                    Text(airport.code)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 6))
                    Text(airport.city)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.label)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.hint)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            HStack(spacing: 24) {
                ForEach(TrackerDirection.allCases) { dir in
                    Button { direction = dir } label: {
                        Text(dir.rawValue)
                            .font(.system(size: 15, weight: direction == dir ? .semibold : .regular))
                            .foregroundColor(direction == dir ? Theme.label : Theme.sublabel)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            scheduleHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(scheduleFlights) { flight in
                        scheduleRow(flight)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    private var scheduleHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Text(direction == .departures ? "Departs" : "Arrives")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .frame(width: 90, alignment: .leading)
            Text(direction == .departures ? "To" : "From")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            Text("Status")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 72, alignment: .leading)
            Text("Flight")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .foregroundColor(Theme.sublabel)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    private func scheduleRow(_ flight: TrackedFlight) -> some View {
        HStack(alignment: .center) {
            Text(flight.time)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 90, alignment: .leading)
            Text(flight.airportCode)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            Text(flight.status.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(flight.status.color)
                .frame(width: 72, alignment: .leading)
            HStack(spacing: 6) {
                AirlineIconView(code: flight.airlineCode, size: 22)
                Text(flight.flightNumber)
                    .font(.system(size: 14, weight: .medium))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var flightNumberTab: some View {
        VStack(spacing: 16) {
            TextField("Enter flight number (e.g. EK 602)", text: $flightNumberQuery)
                .font(.system(size: 16))
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
                .padding(.horizontal, 16)
                .padding(.top, 20)

            if flightNumberQuery.count >= 2 {
                let matched = scheduleFlights.filter {
                    $0.flightNumber.lowercased().contains(flightNumberQuery.lowercased())
                }
                if matched.isEmpty {
                    placeholderResult(icon: "airplane", title: "No flights found",
                                      subtitle: "Check the flight number and try again")
                } else {
                    ForEach(matched) { scheduleRow($0) }
                }
            } else {
                placeholderResult(icon: "magnifyingglass", title: "Search by flight number",
                                  subtitle: "Enter airline code and number, e.g. QR 614")
            }
            Spacer()
        }
    }

    private var routeTab: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                routeAirportField(label: "From", airport: routeFrom) {
                    routeFrom = $0
                }
                Image(systemName: "arrow.right")
                    .foregroundColor(Theme.hint)
                routeAirportField(label: "To", airport: routeTo) {
                    routeTo = $0
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            let matched = scheduleFlights.filter { $0.airportCode == routeTo.code }
            if matched.isEmpty {
                placeholderResult(icon: "map", title: "No flights on this route today",
                                  subtitle: "\(routeFrom.code) → \(routeTo.code)")
            } else {
                scheduleHeader
                Divider()
                ForEach(matched) { scheduleRow($0) }
            }
            Spacer()
        }
    }

    private func routeAirportField(label: String, airport: Airport, onSelect: @escaping (Airport) -> Void) -> some View {
        Menu {
            ForEach(AirportCatalog.all) { ap in
                Button(ap.label) { onSelect(ap) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundColor(Theme.sublabel)
                Text(airport.code).font(.system(size: 18, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5), lineWidth: 0.5))
        }
    }

    private func placeholderResult(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(Theme.hint)
            Text(title).font(.system(size: 15, weight: .medium))
            Text(subtitle).font(.system(size: 13)).foregroundColor(Theme.sublabel)
        }
        .padding(.vertical, 40)
    }
}

// Shared airport picker (used by FlightsListView + tracker)
struct AirportPickerSheet: View {
    let title: String
    let selected: Airport
    let onSelect: (Airport) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var airports: [Airport] {
        AirportCatalog.search(search)
    }

    var body: some View {
        NavigationStack {
            List(airports) { airport in
                Button {
                    onSelect(airport)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(airport.label)
                                .font(.system(size: 15, weight: .medium))
                            Text(airport.country)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.sublabel)
                        }
                        Spacer()
                        if airport.code == selected.code {
                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search city or airport code")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
