import SwiftUI

struct FlightsListView: View {
    @StateObject private var vm = FlightsViewModel()
    @State private var showPassengers = false
    @State private var airportPicker: AirportPickerTarget?
    @State private var showFlightTracker = false
    @State private var showPriceAlerts = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if vm.hasSearched && !vm.searchFormExpanded {
                        collapsedSearchBar
                    }

                    if vm.searchFormExpanded || !vm.hasSearched {
                        searchForm
                    }

                    if !vm.hasSearched {
                        travelDealsSection
                        popularToolsSection
                    }

                    if vm.hasSearched {
                        searchResults
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Theme.background)
        }
        .sheet(isPresented: $showPassengers) {
            PassengerPickerSheet(passengers: $vm.query.passengers)
        }
        .sheet(item: $airportPicker) { target in
            airportPickerSheet(for: target)
        }
        .sheet(isPresented: $showFlightTracker) {
            FlightTrackerView(defaultAirport: vm.query.from)
        }
        .sheet(isPresented: $showPriceAlerts) {
            PriceAlertsView(defaultOrigin: vm.query.from, defaultDestination: vm.query.to)
        }
    }

    // MARK: - Collapsed search bar

    private var collapsedSearchBar: some View {
        Button { withAnimation { vm.searchFormExpanded = true } } label: {
            HStack(spacing: 12) {
                Image(systemName: "airplane")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(vm.collapsedSummaryTitle) · \(vm.collapsedSummaryDates)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.label)
                    Text(vm.collapsedSummaryMeta)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.hint)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Search form

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search Flights")
                .font(.system(size: 24, weight: .bold))

            tripTypeTabs

            switch vm.query.tripType {
            case .multiCity: multiCityForm
            default: standardRouteForm
            }

            filterChips

            Button(action: vm.search) {
                HStack {
                    if vm.isSearching { ProgressView().tint(.white) }
                    Text(vm.isSearching ? "Searching…" : "Search Flights")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(vm.isSearching || !canSearch)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray5), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, vm.hasSearched && !vm.searchFormExpanded ? 0 : 8)
    }

    private var tripTypeTabs: some View {
        HStack(spacing: 20) {
            ForEach(TripType.allCases) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { vm.query.tripType = type }
                } label: {
                    Text(type.rawValue)
                        .font(.system(size: 14, weight: vm.query.tripType == type ? .semibold : .regular))
                        .foregroundColor(vm.query.tripType == type ? Theme.label : Theme.sublabel)
                        .overlay(alignment: .bottom) {
                            if vm.query.tripType == type {
                                Rectangle()
                                    .fill(Theme.label)
                                    .frame(height: 2)
                                    .offset(y: 8)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var standardRouteForm: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                airportButton(label: "From", airport: vm.query.from, target: .from)
                Button(action: vm.swapAirports) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
                airportButton(label: "To", airport: vm.query.to, target: .to)
            }

            HStack(spacing: 10) {
                dateField(title: "Depart", date: $vm.query.departDate)
                if vm.query.tripType == .roundTrip {
                    dateField(title: "Return", date: $vm.query.returnDate)
                }
            }
        }
    }

    private var multiCityForm: some View {
        VStack(spacing: 12) {
            ForEach(Array(vm.query.multiCityLegs.enumerated()), id: \.element.id) { index, leg in
                multiCityLegCard(index: index + 1, leg: leg)
            }
            Button(action: vm.addMultiCityLeg) {
                Text("+ Add another")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(vm.query.multiCityLegs.count >= 5)
        }
    }

    private func multiCityLegCard(index: Int, leg: MultiCityLeg) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Flight \(index)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if vm.query.multiCityLegs.count > 2 {
                    Button { vm.removeMultiCityLeg(leg.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.sublabel)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                legLocationField(legID: leg.id, isFrom: true, airport: leg.from)
                Button { vm.swapLeg(leg.id) } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
                legLocationField(legID: leg.id, isFrom: false, airport: leg.to)
            }

            if let binding = legDateBinding(leg.id) {
                dateField(title: "Date", date: binding)
            }
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func legLocationField(legID: UUID, isFrom: Bool, airport: Airport) -> some View {
        Button {
            airportPicker = .multiCityLeg(legID: legID, isFrom: isFrom)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(isFrom ? "From" : "To")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.sublabel)
                Text("\(airport.city) \(airport.country) (\(airport.code))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func legDateBinding(_ legID: UUID) -> Binding<Date>? {
        guard let index = vm.query.multiCityLegs.firstIndex(where: { $0.id == legID }) else { return nil }
        return Binding(
            get: { vm.query.multiCityLegs[index].date },
            set: { vm.query.multiCityLegs[index].date = $0 }
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showPassengers = true } label: {
                    filterChipLabel("\(vm.query.passengers.total) traveler\(vm.query.passengers.total > 1 ? "s" : "")", showClear: false)
                }
                .buttonStyle(.plain)

                Menu {
                    Picker("Cabin", selection: $vm.query.cabinClass) {
                        Text("Economy").tag("Economy")
                        Text("Business").tag("Business")
                    }
                } label: {
                    filterChipLabel(vm.query.cabinClass, showClear: false)
                }

                Menu {
                    Picker("Stops", selection: $vm.query.stopsFilter) {
                        ForEach(StopsFilter.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                } label: {
                    filterChipLabel(vm.query.stopsFilter.rawValue, showClear: false)
                }
            }
        }
    }

    private func filterChipLabel(_ text: String, showClear: Bool) -> some View {
        let isTravelers = text.contains("traveler")
        return HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
            if showClear {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            } else {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundColor(isTravelers ? .white : Theme.label)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(isTravelers ? Theme.label : Color(.systemGray5)))
    }

    // MARK: - Travel deals

    private var travelDealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Travel deals under $\(FlightDealsCatalog.deals.map(\.priceUSD).max() ?? 400)")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(FlightDealsCatalog.deals(from: vm.query.from.code)) { deal in
                        FlightDealCard(deal: deal) {
                            vm.applyDeal(deal)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Button { /* explore */ } label: {
                Text("Explore more ›")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Popular tools

    private var popularToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular tools")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    toolCard(
                        title: "Price Alerts",
                        subtitle: "Know when prices change",
                        icon: "bell.badge.fill",
                        iconColor: .yellow,
                        action: { showPriceAlerts = true }
                    )
                    toolCard(
                        title: "Flight Tracker",
                        subtitle: "See real-time flight status",
                        icon: "airplane.circle.fill",
                        iconColor: Theme.accent,
                        action: { showFlightTracker = true }
                    )
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func toolCard(title: String, subtitle: String, icon: String, iconColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(height: 100)
                    Image(systemName: icon)
                        .font(.system(size: 40))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.label)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.sublabel)
                    .lineLimit(2)
            }
            .frame(width: 180, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            resultsHeader
                .padding(.horizontal, 16)

            if vm.isSearching {
                loadingState
            } else if vm.query.tripType == .multiCity {
                multiCityResults
            } else if vm.visibleFlights.isEmpty {
                emptyResults
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(vm.visibleFlights) { flight in
                        FlightCard(
                            flight: flight,
                            passengers: vm.query.passengers,
                            isRoundTrip: vm.query.tripType == .roundTrip,
                            detailContext: detailContext(for: flight, departDate: vm.query.departDate)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var multiCityResults: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(Array(vm.multiCityResults.enumerated()), id: \.element.id) { index, result in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Flight \(index + 1): \(result.leg.from.code) → \(result.leg.to.code)")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 16)
                    if result.flights.isEmpty {
                        Text("No flights found for this leg")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.sublabel)
                            .padding(.horizontal, 16)
                    } else {
                        ForEach(result.flights.prefix(5)) { flight in
                            FlightCard(
                                flight: flight,
                                passengers: vm.query.passengers,
                                isRoundTrip: false,
                                detailContext: detailContext(for: flight, departDate: result.leg.date)
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private func detailContext(for flight: Flight, departDate: Date) -> FlightDetailContext {
        FlightDetailContext(
            flight: flight,
            passengers: vm.query.passengers,
            isRoundTrip: vm.query.tripType == .roundTrip,
            departDate: departDate,
            returnDate: vm.query.returnDate
        )
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.headerSummary)
                .font(.system(size: 14))
                .foregroundColor(Theme.sublabel)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FlightSortFilter.allCases) { filter in
                        ChipButton(title: filter.rawValue, isSelected: vm.sortFilter == filter) {
                            vm.sortFilter = filter
                            vm.refreshSort()
                        }
                    }
                }
            }
        }
    }

    private var canSearch: Bool {
        if vm.query.tripType == .multiCity {
            return vm.query.multiCityLegs.allSatisfy { $0.from.code != $0.to.code }
        }
        return vm.query.from.code != vm.query.to.code
    }

    // MARK: - Helpers

    private func airportButton(label: String, airport: Airport, target: AirportPickerTarget) -> some View {
        Button { airportPicker = target } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundColor(Theme.sublabel)
                Text(airport.code).font(.system(size: 22, weight: .bold)).foregroundColor(Theme.label)
                Text(airport.city).font(.system(size: 12)).foregroundColor(Theme.sublabel).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func dateField(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundColor(Theme.sublabel)
            DatePicker("", selection: date, in: Date()..., displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5), lineWidth: 0.5))
    }

    @ViewBuilder
    private func airportPickerSheet(for target: AirportPickerTarget) -> some View {
        switch target {
        case .from:
            AirportPickerSheet(title: "Flying from", selected: vm.query.from) { vm.query.from = $0 }
        case .to:
            AirportPickerSheet(title: "Flying to", selected: vm.query.to) { vm.query.to = $0 }
        case .multiCityLeg(let legID, let isFrom):
            let leg = vm.query.multiCityLegs.first { $0.id == legID }
            let airport = isFrom ? (leg?.from ?? vm.query.from) : (leg?.to ?? vm.query.to)
            AirportPickerSheet(title: isFrom ? "Flying from" : "Flying to", selected: airport) { selected in
                guard let i = vm.query.multiCityLegs.firstIndex(where: { $0.id == legID }) else { return }
                if isFrom { vm.query.multiCityLegs[i].from = selected }
                else { vm.query.multiCityLegs[i].to = selected }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Fetching live schedules…")
                .font(.system(size: 14))
                .foregroundColor(Theme.sublabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 32))
                .foregroundColor(Theme.hint)
            Text("No flights match this filter")
                .font(.system(size: 15, weight: .medium))
            Text("Try a different filter or search again")
                .font(.system(size: 13))
                .foregroundColor(Theme.sublabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Airport picker target

private enum AirportPickerTarget: Identifiable {
    case from, to
    case multiCityLeg(legID: UUID, isFrom: Bool)

    var id: String {
        switch self {
        case .from: return "from"
        case .to: return "to"
        case .multiCityLeg(let id, let isFrom): return "leg-\(id)-\(isFrom)"
        }
    }
}

// MARK: - Passenger picker

private struct PassengerPickerSheet: View {
    @Binding var passengers: FlightPassengers
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                passengerRow(title: "Adults", subtitle: "12+", value: $passengers.adults, min: 1, max: 9)
                passengerRow(title: "Children", subtitle: "2–11", value: $passengers.children, min: 0, max: 8)
                passengerRow(title: "Infants", subtitle: "Under 2", value: $passengers.infants, min: 0, max: 4)
            }
            .navigationTitle("Passengers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func passengerRow(title: String, subtitle: String, value: Binding<Int>, min: Int, max: Int) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.sublabel)
            }
            Spacer()
            HStack(spacing: 16) {
                Button {
                    if value.wrappedValue > min { value.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(value.wrappedValue > min ? Theme.accent : Theme.hint)
                }
                .buttonStyle(.plain)
                Text("\(value.wrappedValue)")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(minWidth: 24)
                Button {
                    if value.wrappedValue < max { value.wrappedValue += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(value.wrappedValue < max ? Theme.accent : Theme.hint)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Flight Card
struct FlightCard: View {
    let flight: Flight
    let passengers: FlightPassengers
    let isRoundTrip: Bool
    let detailContext: FlightDetailContext

    private var totalPrice: Int {
        passengers.totalPrice(for: flight.priceUSD)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AirlineIconsRow(
                    codes: isRoundTrip ? flight.allAirlineCodes : flight.outboundAirlineCodes,
                    size: 36,
                    overlap: 10
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(airlineSummary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.label)
                        .lineLimit(1)
                    Text(flight.stopsLabel)
                        .font(.system(size: 11))
                        .foregroundColor(flight.stops == 0 ? Theme.accent : .orange)
                }
                Spacer()
                PillBadge(text: flight.cabinClass, foreground: Theme.sublabel, background: Color(.systemGray5))
            }
            .padding(.bottom, 12)

            HStack(alignment: .center, spacing: 8) {
                CityBlock(code: flight.originCode, time: flight.departure)
                routeLine(duration: flight.duration, stops: flight.stops)
                CityBlock(code: flight.destinationCode, time: flight.arrival)
            }

            if isRoundTrip, let retDep = flight.returnDeparture, let retArr = flight.returnArrival {
                Divider().padding(.vertical, 10)
                HStack(alignment: .center, spacing: 8) {
                    CityBlock(code: flight.destinationCode, time: retDep)
                    routeLine(duration: flight.returnDurationMinutes.map { formatMin($0) } ?? "—", stops: flight.stops)
                    CityBlock(code: flight.originCode, time: retArr)
                }
                Text("Return leg")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.hint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            Divider().padding(.vertical, 10)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("$\(totalPrice)")
                        .font(.system(size: 20, weight: .bold))
                    Text(isRoundTrip ? "total round trip" : "total · \(passengers.summary)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.sublabel)
                }
                Spacer()
                NavigationLink {
                    FlightDetailView(context: detailContext)
                } label: {
                    Text("Details")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }

    private var airlineSummary: String {
        let codes = isRoundTrip ? flight.allAirlineCodes : flight.outboundAirlineCodes
        if codes.count == 1 { return flight.airline }
        return codes.compactMap { code in
            flight.outboundSegments.first { $0.iataCode == code }?.airline
                ?? flight.returnSegments.first { $0.iataCode == code }?.airline
        }.joined(separator: " · ")
    }

    private func routeLine(duration: String, stops: Int) -> some View {
        VStack(spacing: 3) {
            Text(duration).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.hint)
            HStack(spacing: 2) {
                Rectangle().fill(Color(.systemGray3)).frame(maxWidth: .infinity).frame(height: 1)
                Image(systemName: "airplane").font(.system(size: 12)).foregroundColor(Theme.hint).rotationEffect(.degrees(45))
            }
            Text(stops == 0 ? "Non-stop" : "\(stops) Stop\(stops > 1 ? "s" : "")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(stops == 0 ? Theme.accent : .orange)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatMin(_ m: Int) -> String {
        m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}

struct CityBlock: View {
    let code: String
    let time: String
    var body: some View {
        VStack(spacing: 2) {
            Text(code).font(.system(size: 22, weight: .bold))
            Text(time).font(.system(size: 12)).foregroundColor(Theme.sublabel)
        }
        .frame(minWidth: 48)
    }
}

struct AirlineBadge: View {
    let code: String
    let color: Color
    var body: some View { AirlineIconView(code: code, size: 30) }
}

#Preview { FlightsListView() }
