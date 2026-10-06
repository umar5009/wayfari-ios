import SwiftUI

// MARK: - Full tour plan card stack (shown in chat)
struct TourPlanCard: View {
    let plan: TourPlan
    @State private var selectedSection: PlanSection = .overview

    private enum PlanSection: String, CaseIterable {
        case overview = "Overview"
        case flights = "Flights"
        case hotels = "Hotels"
        case itinerary = "Itinerary & map"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sectionPicker
            Divider()
            content
                .padding(14)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray5), lineWidth: 0.5))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .foregroundColor(Theme.accent)
                Text(plan.request.title)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
            }
            Text(plan.summary)
                .font(.system(size: 13))
                .foregroundColor(Theme.sublabel)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                let travelers = plan.request.travelers ?? 2
                MetaChip(icon: "person.2", text: "\(travelers) traveller\(travelers == 1 ? "" : "s")")
                MetaChip(icon: "moon.stars", text: "\(plan.request.nights) nights")
                MetaChip(icon: "banknote", text: "$\(plan.estimatedBudgetMin)–$\(plan.estimatedBudgetMax)")
            }
        }
        .padding(14)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PlanSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedSection = section }
                    } label: {
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedSection == section ? .white : Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedSection == section ? Theme.accent : Theme.accent.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .overview: OverviewSection(plan: plan)
        case .flights: FlightsSection(
            flights: plan.flights,
            originCountry: plan.request.originCountry ?? "your departure country",
            preferredCity: plan.request.originCity
        )
        case .hotels:
            HotelsSection(
                hotels: plan.hotels,
                nights: plan.request.nights,
                destinations: plan.request.destinations
            )
        case .itinerary: ItinerarySection(plan: plan)
        }
    }
}

// MARK: - Route + priced places map (lives inside the itinerary tab)
private struct RouteMapSection: View {
    let stops: [TourRouteStop]
    let placePins: [TourPlacePin]

    @State private var fitTarget: TourRouteMapView.FitTarget = .journey
    @State private var showsJourneySteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Journey map · home → cities → home")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.hint)
                Spacer(minLength: 8)
                if !placePins.isEmpty {
                    fitPicker
                }
            }

            if stops.count >= 2 {
                TourRouteMapView(stops: stops, placePins: placePins, fitTarget: fitTarget)
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
            }

            HStack(spacing: 12) {
                MapLegendItem(color: Color(hex: "3949AB"), label: "Home")
                MapLegendItem(color: Theme.accent, label: "Arrival")
                MapLegendItem(color: Color(hex: "EF6C00"), label: "City stop")
                MapLegendItem(color: .teal, label: "Ticketed place")
                MapLegendItem(color: .green, label: "Free")
            }
            .font(.system(size: 10))

            Text(routeSummary)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.label)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsJourneySteps.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Journey steps (\(stops.count))")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: showsJourneySteps ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)

            if showsJourneySteps {
                VStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        RouteStopRow(stop: stop, isLast: index == stops.count - 1)
                    }
                }
                .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var fitPicker: some View {
        HStack(spacing: 4) {
            ForEach([TourRouteMapView.FitTarget.journey, .places], id: \.self) { target in
                let isSelected = fitTarget == target
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { fitTarget = target }
                } label: {
                    Text(target == .journey ? "Full route" : "Places")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .white : Theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(isSelected ? Theme.accent : Theme.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var routeSummary: String {
        let cities = stops.map(\.city)
        guard cities.count >= 2 else { return "Route will appear once your plan cities are ready." }
        return cities.joined(separator: " → ")
    }
}

private struct MapLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundColor(Theme.hint)
        }
    }
}

private struct RouteStopRow: View {
    let stop: TourRouteStop
    let isLast: Bool

    private var tint: Color {
        switch stop.kind {
        case .departure, .returnHome: return Color(hex: "3949AB")
        case .arrival: return Theme.accent
        case .internalStop: return Color(hex: "EF6C00")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(tint).frame(width: 28, height: 28)
                    Text("\(stop.order)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2, height: 28)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: stop.kind.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tint)
                    Text(stop.kind.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tint)
                }
                Text("\(stop.city), \(stop.country)")
                    .font(.system(size: 14, weight: .semibold))
                Text(stop.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.sublabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, isLast ? 12 : 0)
    }
}

// MARK: - Overview
private struct OverviewSection: View {
    let plan: TourPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoRow(icon: "sun.max", title: "Best season", value: plan.bestSeason)
            InfoRow(icon: "dollarsign.circle", title: "Currency", value: plan.currency)
            InfoRow(icon: "doc.text", title: "Visa", value: plan.visaNote)

            Text("Quick tips")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 4)
            ForEach(Array(plan.tips.enumerated()), id: \.offset) { _, tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.accent)
                        .padding(.top, 2)
                    Text(tip)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sublabel)
                }
            }

            Text("Est. total per person (flights + hotel + food + tickets)")
                .font(.system(size: 12))
                .foregroundColor(Theme.hint)
                .padding(.top, 4)
            Text("$\(plan.estimatedBudgetMin) – $\(plan.estimatedBudgetMax)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.accent)
        }
    }
}

// MARK: - Flights
private struct FlightsSection: View {
    let flights: [TourFlightOption]
    let originCountry: String
    let preferredCity: String?

    private var preferredNote: String {
        preferredCity.map { " · \($0) listed first" } ?? ""
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Major airports in \(originCountry)\(preferredNote)")
                .font(.system(size: 12))
                .foregroundColor(Theme.hint)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(originGroups, id: \.code) { group in
                FlightOriginSection(
                    city: group.city,
                    code: group.code,
                    flights: group.flights,
                    isPreferred: preferredCity?.caseInsensitiveCompare(group.city) == .orderedSame
                )
            }
        }
    }

    private var originGroups: [(city: String, code: String, flights: [TourFlightOption])] {
        var seen: [String] = []
        for flight in flights where !seen.contains(flight.originCode) {
            seen.append(flight.originCode)
        }
        return seen.map { code in
            let matches = flights.filter { $0.originCode == code }
            return (matches.first?.originCity ?? code, code, matches)
        }
    }
}

private struct FlightOriginSection: View {
    let city: String
    let code: String
    let flights: [TourFlightOption]
    var isPreferred: Bool = false
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(city) (\(code))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.label)
                            if isPreferred {
                                Text("Your city")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Theme.accent, in: Capsule())
                            }
                        }
                        if let minPrice = flights.map(\.priceUSD).min(),
                           let maxPrice = flights.map(\.priceUSD).max() {
                            Text("\(flights.count) cabin options · $\(minPrice)–$\(maxPrice)")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.sublabel)
                        }
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
                .padding(12)
                .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(flights) { flight in
                    FlightOptionRow(flight: flight)
                }
            }
        }
        .onAppear {
            if isPreferred { expanded = true }
        }
    }
}

private struct FlightOptionRow: View {
    let flight: TourFlightOption

    private var tierColor: Color {
        switch flight.tier {
        case .budget:  return Color(hex: "2E7D32")
        case .value:   return Color(hex: "1A5CAA")
        case .premium: return Color(hex: "6A1B9A")
        case .luxury:  return Color(hex: "8A6000")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PillBadge(text: flight.tier.rawValue, foreground: tierColor, background: tierColor.opacity(0.12))
                Spacer()
                Text("$\(flight.priceUSD)")
                    .font(.system(size: 18, weight: .bold))
            }
            HStack(spacing: 8) {
                Image(systemName: flight.tier.icon)
                    .foregroundColor(tierColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(flight.airline) · \(flight.cabin)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(flight.route)  ·  \(flight.duration)  ·  \(flight.stops)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                }
            }
            HStack {
                Text("\(flight.departure) → \(flight.arrival)")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            Text(flight.notes)
                .font(.system(size: 11))
                .foregroundColor(Theme.hint)
        }
        .padding(12)
        .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Hotels
private struct HotelsSection: View {
    let hotels: [TourHotelOption]
    let nights: Int
    let destinations: [String]

    private var destinationCount: Int { max(destinations.count, 1) }

    var body: some View {
        VStack(spacing: 10) {
            let cities = Set(hotels.map(\.city)).sorted()
            Text("\(hotels.count) options across \(cities.count) cities · 3★ to 5★ · \(nights) nights")
                .font(.system(size: 12))
                .foregroundColor(Theme.hint)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach([3, 4, 5], id: \.self) { stars in
                let tierHotels = hotels.filter { $0.stars == stars }
                if !tierHotels.isEmpty {
                    HStack {
                        Text("\(String(repeating: "★", count: stars)) \(tierName(stars))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(stars == 5 ? Color(hex: "C9A227") : Theme.label)
                        Spacer()
                        Text("\(tierHotels.count) options")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.hint)
                    }
                    .padding(.top, 4)

                    ForEach(citiesIn(tierHotels), id: \.self) { city in
                        Text(city)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)

                        ForEach(tierHotels.filter { $0.city == city }) { hotel in
                            HotelOptionRow(
                                hotel: hotel,
                                nights: destinationCount > 1 ? max(nights / destinationCount, 1) : nights,
                                isEstimatedSplit: destinationCount > 1
                            )
                        }
                    }
                }
            }
        }
    }

    private func citiesIn(_ hotels: [TourHotelOption]) -> [String] {
        var seen: [String] = []
        for hotel in hotels where !seen.contains(hotel.city) {
            seen.append(hotel.city)
        }
        return seen
    }

    private func tierName(_ stars: Int) -> String {
        switch stars {
        case 3: return "Budget"
        case 4: return "Comfort"
        default: return "Luxury"
        }
    }
}

private struct HotelOptionRow: View {
    let hotel: TourHotelOption
    let nights: Int
    let isEstimatedSplit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(repeating: "★", count: hotel.stars))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "C9A227"))
                    Text(hotel.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(hotel.neighbourhood) · \(hotel.city)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(hotel.pricePerNight)")
                        .font(.system(size: 18, weight: .bold))
                    Text("/night")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.hint)
                    Text("$\(hotel.pricePerNight * nights) \(isEstimatedSplit ? "est. stay" : "total")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
            }
            Text(hotel.style)
                .font(.system(size: 12))
                .foregroundColor(Theme.sublabel)
            FlowAmenities(items: hotel.amenities)
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.orange)
                Text(String(format: "%.1f guest rating", hotel.rating))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.hint)
            }
        }
        .padding(12)
        .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FlowAmenities: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(items: items)
    }
}

/// Simple wrapping chip row without UIKit dependency.
private struct FlexibleWrap: View {
    let items: [String]
    var body: some View {
        // Fixed 2-row style chips for predictability in chat cards
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(items.prefix(3), id: \.self) { item in
                    Text(item)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.sublabel)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5), in: Capsule())
                }
            }
            if items.count > 3 {
                HStack(spacing: 6) {
                    ForEach(items.dropFirst(3), id: \.self) { item in
                        Text(item)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.sublabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5), in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Itinerary
private struct ItinerarySection: View {
    let plan: TourPlan
    @State private var expandedDay: Int? = 1

    private var days: [ItineraryDay] { plan.days }

    var body: some View {
        VStack(spacing: 10) {
            RouteMapSection(stops: plan.routeStops, placePins: plan.placePins)

            Divider().padding(.vertical, 2)

            let ticketTotal = days.reduce(0) { $0 + $1.dayTicketsTotal }
            Text("Day-by-day plan · \(plan.placePins.count) places pinned · attraction tickets ≈ $\(ticketTotal) total")
                .font(.system(size: 12))
                .foregroundColor(Theme.hint)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(days) { day in
                DayCard(day: day, isExpanded: expandedDay == day.dayNumber) {
                    withAnimation(.spring(response: 0.3)) {
                        expandedDay = expandedDay == day.dayNumber ? nil : day.dayNumber
                    }
                }
            }
        }
    }
}

private struct DayCard: View {
    let day: ItineraryDay
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    ZStack {
                        Circle().fill(Theme.accent).frame(width: 28, height: 28)
                        Text("\(day.dayNumber)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.label)
                        Text("\(day.city) · \(day.theme)")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sublabel)
                    }
                    Spacer()
                    if day.dayTicketsTotal > 0 {
                        Text("$\(day.dayTicketsTotal)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.accent)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.hint)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(day.activities) { activity in
                        ActivityRow(activity: activity)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.hint)
                        Text(day.mealsHint)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.sublabel)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.hint)
                        Text(day.transportHint)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.sublabel)
                    }
                }
                .padding(12)
            }
        }
        .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ActivityRow: View {
    let activity: ItineraryActivity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(activity.time)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.accent)
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(activity.name)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(activity.ticketLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(activity.ticketPriceUSD == nil || activity.ticketPriceUSD == 0
                                         ? Color(hex: "2E7D32") : Theme.label)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (activity.ticketPriceUSD == nil || activity.ticketPriceUSD == 0
                             ? Color(hex: "E8F5E9") : Color(.systemGray5)),
                            in: Capsule()
                        )
                }
                Text("\(activity.category) · \(activity.durationHours.clean)h")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.hint)
                Text(activity.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.sublabel)
                if let tip = activity.tip {
                    Text("Tip: \(tip)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }
}

// MARK: - Shared bits
private struct MetaChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(Theme.sublabel)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.secondary, in: Capsule())
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.hint)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension Double {
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(format: "%.1f", self)
    }
}
