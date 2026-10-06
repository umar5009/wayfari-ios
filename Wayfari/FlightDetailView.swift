import SwiftUI

struct FlightDetailContext: Identifiable, Hashable {
    let id: UUID
    let flight: Flight
    let passengers: FlightPassengers
    let isRoundTrip: Bool
    let departDate: Date
    let returnDate: Date

    init(flight: Flight, passengers: FlightPassengers, isRoundTrip: Bool, departDate: Date, returnDate: Date) {
        self.id = flight.id
        self.flight = flight
        self.passengers = passengers
        self.isRoundTrip = isRoundTrip
        self.departDate = departDate
        self.returnDate = returnDate
    }
}

struct FlightDetailView: View {
    let context: FlightDetailContext
    @Environment(\.openURL) private var openURL

    private var flight: Flight { context.flight }
    private var totalPrice: Int { context.passengers.totalPrice(for: flight.priceUSD) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryHeader
                outboundSection
                if context.isRoundTrip, !flight.returnSegments.isEmpty {
                    returnSection
                }
                priceBreakdown
                bookingSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Flight Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                AirlineIconsRow(codes: flight.allAirlineCodes, size: 36, overlap: 12)
                Spacer()
                PillBadge(
                    text: flight.cabinClass,
                    foreground: Theme.sublabel,
                    background: Color(.systemGray5)
                )
            }

            Text(routeTitle)
                .font(.system(size: 20, weight: .bold))

            HStack(spacing: 16) {
                detailChip(icon: "calendar", text: dateRangeLabel)
                detailChip(icon: "person.2", text: context.passengers.summary)
                detailChip(icon: "clock", text: flight.duration)
            }

            if flight.stops > 0 {
                Text("\(flight.stopsLabel) · Operated by \(operatorsLabel(codes: flight.outboundAirlineCodes))")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
            } else {
                Text("Non-stop · \(flight.airline)")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.sublabel)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }

    private var routeTitle: String {
        if context.isRoundTrip {
            return "\(flight.originCode) ⇄ \(flight.destinationCode)"
        }
        return "\(flight.originCode) → \(flight.destinationCode)"
    }

    private var dateRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM yyyy"
        if context.isRoundTrip {
            return "\(fmt.string(from: context.departDate)) – \(fmt.string(from: context.returnDate))"
        }
        return fmt.string(from: context.departDate)
    }

    private func detailChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Theme.sublabel)
    }

    private func operatorsLabel(codes: [String]) -> String {
        codes.compactMap { code in
            flight.outboundSegments.first { $0.iataCode == code }?.airline
        }.joined(separator: " + ")
    }

    // MARK: - Leg sections

    private var outboundSection: some View {
        legSection(
            title: "Outbound",
            subtitle: "\(flight.originCity) to \(flight.destinationCity)",
            date: context.departDate,
            segments: flight.outboundSegments,
            airlineCodes: flight.outboundAirlineCodes
        )
    }

    private var returnSection: some View {
        legSection(
            title: "Return",
            subtitle: "\(flight.destinationCity) to \(flight.originCity)",
            date: context.returnDate,
            segments: flight.returnSegments,
            airlineCodes: flight.returnAirlineCodes
        )
    }

    private func legSection(
        title: String,
        subtitle: String,
        date: Date,
        segments: [FlightSegment],
        airlineCodes: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sublabel)
                }
                Spacer()
                AirlineIconsRow(codes: airlineCodes, size: 26, overlap: 8)
            }

            Text(formattedDate(date))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.hint)

            VStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    segmentRow(segment)
                    if index < segments.count - 1, let layover = segment.layoverLabel {
                        layoverRow(label: layover, at: segment.destinationCode)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }

    private func segmentRow(_ segment: FlightSegment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .stroke(Theme.accent, lineWidth: 2)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 10)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.departure)
                            .font(.system(size: 18, weight: .bold))
                        Text("\(segment.originCode) · \(segment.originCity)")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.sublabel)
                    }
                    Spacer()
                    Text(segment.durationLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.hint)
                }

                HStack(spacing: 8) {
                    AirlineIconView(code: segment.iataCode, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(segment.airline)
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(segment.flightNumber) · \(flight.cabinClass)")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sublabel)
                    }
                    Spacer()
                    Button {
                        openURL(AirlineCatalog.segmentBookingURL(
                            segment: segment,
                            departDate: context.departDate,
                            adults: context.passengers.adults
                        ))
                    } label: {
                        HStack(spacing: 4) {
                            Text("Book")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.arrival)
                        .font(.system(size: 18, weight: .bold))
                    Text("\(segment.destinationCode) · \(segment.destinationCity)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func layoverRow(label: String, at airport: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 2, height: 20)
                .padding(.leading, 4)
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("\(label) in \(airport)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.orange)
        }
        .padding(.vertical, 6)
        .padding(.leading, 2)
    }

    // MARK: - Price

    private var priceBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Price summary")
                .font(.system(size: 17, weight: .bold))

            if context.passengers.adults > 0 {
                priceRow(
                    label: "\(context.passengers.adults) Adult\(context.passengers.adults > 1 ? "s" : "")",
                    amount: flight.priceUSD * context.passengers.adults
                )
            }
            if context.passengers.children > 0 {
                let childFare = Int(Double(flight.priceUSD) * 0.75)
                priceRow(
                    label: "\(context.passengers.children) Child\(context.passengers.children > 1 ? "ren" : "")",
                    amount: childFare * context.passengers.children
                )
            }
            if context.passengers.infants > 0 {
                let infantFare = Int(Double(flight.priceUSD) * 0.10)
                priceRow(
                    label: "\(context.passengers.infants) Infant\(context.passengers.infants > 1 ? "s" : "")",
                    amount: infantFare * context.passengers.infants
                )
            }

            Divider()

            HStack {
                Text(context.isRoundTrip ? "Total round trip" : "Total")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("$\(totalPrice)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }

    private func priceRow(label: String, amount: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Theme.sublabel)
            Spacer()
            Text("$\(amount)")
                .font(.system(size: 14, weight: .medium))
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, d MMMM yyyy"
        return fmt.string(from: date)
    }

    // MARK: - Book on airline website

    private var bookingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Book this itinerary")
                .font(.system(size: 17, weight: .bold))

            Text("Continue on the airline website to view live schedules and complete your booking.")
                .font(.system(size: 13))
                .foregroundColor(Theme.sublabel)

            ForEach(bookingOptions, id: \.code) { option in
                Button {
                    openURL(option.url)
                } label: {
                    HStack(spacing: 12) {
                        AirlineIconView(code: option.code, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.label)
                            Text(option.subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.sublabel)
                        }
                        Spacer()
                        Image(systemName: "safari")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.accent)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct BookingOption {
        let code: String
        let title: String
        let subtitle: String
        let url: URL
    }

    private var bookingOptions: [BookingOption] {
        var options: [BookingOption] = []
        var seen = Set<String>()

        let primaryURL = AirlineCatalog.bookingURL(
            airlineCode: flight.iataCode,
            origin: flight.originCode,
            destination: flight.destinationCode,
            departDate: context.departDate,
            returnDate: context.isRoundTrip ? context.returnDate : nil,
            isRoundTrip: context.isRoundTrip,
            adults: context.passengers.adults
        )
        options.append(BookingOption(
            code: flight.iataCode,
            title: "Continue on \(flight.airline)",
            subtitle: context.isRoundTrip
                ? "\(flight.originCode) ⇄ \(flight.destinationCode) · Round trip"
                : "\(flight.originCode) → \(flight.destinationCode) · One-way",
            url: primaryURL
        ))
        seen.insert(flight.iataCode)

        let allSegments = flight.outboundSegments + flight.returnSegments
        for segment in allSegments where seen.insert(segment.iataCode).inserted {
            let legDate = segment.originCode == flight.originCode || segment.originCode == flight.destinationCode
                ? (segment.originCode == flight.originCode ? context.departDate : context.returnDate)
                : context.departDate
            options.append(BookingOption(
                code: segment.iataCode,
                title: "Book on \(segment.airline)",
                subtitle: "\(segment.flightNumber) · \(segment.originCode) → \(segment.destinationCode)",
                url: AirlineCatalog.segmentBookingURL(
                    segment: segment,
                    departDate: legDate,
                    adults: context.passengers.adults
                )
            ))
        }

        return options
    }
}

#Preview {
    NavigationStack {
        FlightDetailView(
            context: FlightDetailContext(
                flight: SampleData.flights[4],
                passengers: FlightPassengers(adults: 2, children: 1, infants: 0),
                isRoundTrip: false,
                departDate: Date(),
                returnDate: Date()
            )
        )
    }
}
