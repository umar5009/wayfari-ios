import Foundation

// MARK: - Search models

enum TripType: String, CaseIterable, Identifiable {
    case roundTrip = "Round-trip"
    case oneWay = "One-way"
    case multiCity = "Multi-city"

    var id: String { rawValue }
}

enum StopsFilter: String, CaseIterable, Identifiable {
    case any = "Any stops"
    case nonStop = "Non-stop"
    case oneStop = "1 stop max"

    var id: String { rawValue }
}

struct MultiCityLeg: Identifiable, Equatable, Hashable {
    let id: UUID
    var from: Airport
    var to: Airport
    var date: Date

    init(id: UUID = UUID(), from: Airport, to: Airport, date: Date) {
        self.id = id
        self.from = from
        self.to = to
        self.date = date
    }
}

struct Airport: Identifiable, Hashable {
    let code: String
    let city: String
    let country: String

    var id: String { code }
    var label: String { "\(city) (\(code))" }
}

struct FlightPassengers: Equatable, Hashable {
    var adults: Int = 1
    var children: Int = 0
    var infants: Int = 0

    var total: Int { adults + children + infants }

    var summary: String {
        var parts: [String] = []
        if adults > 0 { parts.append("\(adults) Adult\(adults > 1 ? "s" : "")") }
        if children > 0 { parts.append("\(children) Child\(children > 1 ? "ren" : "")") }
        if infants > 0 { parts.append("\(infants) Infant\(infants > 1 ? "s" : "")") }
        return parts.joined(separator: ", ")
    }

    func totalPrice(for perPersonUSD: Int) -> Int {
        let adultTotal = perPersonUSD * adults
        let childTotal = Int(Double(perPersonUSD) * 0.75) * children
        let infantTotal = Int(Double(perPersonUSD) * 0.10) * infants
        return adultTotal + childTotal + infantTotal
    }
}

struct FlightSearchQuery: Equatable {
    var from: Airport
    var to: Airport
    var departDate: Date
    var returnDate: Date
    var tripType: TripType
    var passengers: FlightPassengers
    var cabinClass: String = "Economy"
    var stopsFilter: StopsFilter = .any
    var multiCityLegs: [MultiCityLeg] = []
}

enum FlightSortFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case cheapest = "Cheapest"
    case fastest = "Fastest"
    case nonStop = "Non-stop"
    case morning = "Morning"
    case evening = "Evening"

    var id: String { rawValue }
}

// MARK: - Airport catalog

enum AirportCatalog {
    static let all: [Airport] = [
        Airport(code: "KHI", city: "Karachi", country: "Pakistan"),
        Airport(code: "LHE", city: "Lahore", country: "Pakistan"),
        Airport(code: "ISB", city: "Islamabad", country: "Pakistan"),
        Airport(code: "PEW", city: "Peshawar", country: "Pakistan"),
        Airport(code: "DXB", city: "Dubai", country: "UAE"),
        Airport(code: "AUH", city: "Abu Dhabi", country: "UAE"),
        Airport(code: "SHJ", city: "Sharjah", country: "UAE"),
        Airport(code: "DOH", city: "Doha", country: "Qatar"),
        Airport(code: "IST", city: "Istanbul", country: "Turkey"),
        Airport(code: "LHR", city: "London", country: "UK"),
        Airport(code: "JFK", city: "New York", country: "USA"),
        Airport(code: "SIN", city: "Singapore", country: "Singapore"),
        Airport(code: "BKK", city: "Bangkok", country: "Thailand"),
        Airport(code: "RUH", city: "Riyadh", country: "Saudi Arabia"),
        Airport(code: "JED", city: "Jeddah", country: "Saudi Arabia"),
        Airport(code: "KWI", city: "Kuwait City", country: "Kuwait"),
        Airport(code: "CPH", city: "Copenhagen", country: "Denmark"),
        Airport(code: "FCO", city: "Rome", country: "Italy"),
        Airport(code: "GYD", city: "Baku", country: "Azerbaijan"),
    ]

    static func search(_ query: String) -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.code.lowercased().contains(q) ||
            $0.city.lowercased().contains(q) ||
            $0.country.lowercased().contains(q)
        }
    }
}

// MARK: - Schedule generator

enum FlightScheduleService {
    private static let carriers: [(name: String, code: String, econ: Int, biz: Int)] = [
        ("Emirates", "EK", 220, 680),
        ("Pakistan Int'l Airlines", "PK", 165, 520),
        ("flydubai", "FZ", 135, 0),
        ("Air Arabia", "G9", 118, 0),
        ("Qatar Airways", "QR", 195, 610),
        ("Etihad Airways", "EY", 210, 640),
        ("Turkish Airlines", "TK", 240, 590),
        ("Saudi Arabian Airlines", "SV", 175, 480),
        ("Gulf Air", "GF", 188, 0),
        ("Oman Air", "WY", 200, 550),
    ]

    static func fetchSchedules(for query: FlightSearchQuery) async -> [Flight] {
        try? await Task.sleep(nanoseconds: 900_000_000)

        let distanceFactor = routeFactor(from: query.from.code, to: query.to.code)
        let dateFactor = dayOfWeekFactor(query.departDate)
        let seed = abs((query.from.code + query.to.code + formatted(query.departDate)).hashValue)

        var results: [Flight] = []
        let slots: [(hour: Int, minute: Int, durationMin: Int, stops: Int, cabinOffset: Int)] = [
            (6, 15, baseDuration(distanceFactor) - 10, 0, 0),
            (8, 40, baseDuration(distanceFactor), 0, 1),
            (11, 20, baseDuration(distanceFactor) + 15, 0, 2),
            (14, 5, baseDuration(distanceFactor) + 5, 0, 0),
            (16, 50, baseDuration(distanceFactor) + 25, 1, 1),
            (19, 30, baseDuration(distanceFactor) + 10, 0, 0),
            (21, 10, baseDuration(distanceFactor) + 35, 1, 2),
            (23, 45, baseDuration(distanceFactor) + 20, 0, 1),
            (5, 55, baseDuration(distanceFactor) - 5, 0, 0),
            (13, 0, baseDuration(distanceFactor) + 40, 2, 0),
        ]

        for (index, slot) in slots.enumerated() {
            let carrier = carriers[(seed + index) % carriers.count]
            let cabin = query.cabinClass == "Business" && carrier.biz > 0 ? "Business" : "Economy"
            let base = cabin == "Business" ? carrier.biz : carrier.econ
            guard base > 0 else { continue }

            let tripMultiplier = query.tripType == .roundTrip ? 1.85 : 1.0
            let price = Int(Double(base) * distanceFactor * dateFactor * tripMultiplier) + (index * 7) + (slot.stops * 45)
            let dep = formatTime(hour: slot.hour, minute: slot.minute)
            let arr = formatTime(hour: slot.hour, minute: slot.minute, addMinutes: slot.durationMin)
            let duration = formatDuration(slot.durationMin)

            var returnDep: String?
            var returnArr: String?
            var returnDur: Int?
            var outboundSegs: [FlightSegment] = []
            var returnSegs: [FlightSegment] = []

            outboundSegs = buildSegments(
                primary: carrier,
                from: query.from,
                to: query.to,
                departHour: slot.hour,
                departMinute: slot.minute,
                totalDurationMin: slot.durationMin,
                stops: slot.stops,
                seed: seed + index
            )

            if query.tripType == .roundTrip {
                let retHour = (slot.hour + 6) % 24
                returnDep = formatTime(hour: retHour, minute: (slot.minute + 20) % 60)
                returnDur = slot.durationMin + 10
                returnArr = formatTime(hour: retHour, minute: (slot.minute + 20) % 60, addMinutes: returnDur!)
                returnSegs = buildSegments(
                    primary: carrier,
                    from: query.to,
                    to: query.from,
                    departHour: retHour,
                    departMinute: (slot.minute + 20) % 60,
                    totalDurationMin: returnDur!,
                    stops: slot.stops,
                    seed: seed + index + 50
                )
            }

            results.append(Flight(
                airline: carrier.name,
                iataCode: carrier.code,
                originCity: query.from.city,
                originCode: query.from.code,
                destinationCity: query.to.city,
                destinationCode: query.to.code,
                departure: dep,
                arrival: arr,
                duration: duration,
                durationMinutes: slot.durationMin,
                stops: slot.stops,
                cabinClass: cabin,
                priceUSD: max(price, 89),
                returnDeparture: returnDep,
                returnArrival: returnArr,
                returnDurationMinutes: returnDur,
                outboundSegments: outboundSegs,
                returnSegments: returnSegs
            ))
        }

        if query.cabinClass == "Business" {
            results = results.filter { $0.cabinClass == "Business" }
        }

        switch query.stopsFilter {
        case .any: break
        case .nonStop: results = results.filter { $0.stops == 0 }
        case .oneStop: results = results.filter { $0.stops <= 1 }
        }

        return results
    }

    static func fetchMultiCity(for query: FlightSearchQuery) async -> [(leg: MultiCityLeg, flights: [Flight])] {
        var output: [(leg: MultiCityLeg, flights: [Flight])] = []
        for leg in query.multiCityLegs {
            var legQuery = query
            legQuery.from = leg.from
            legQuery.to = leg.to
            legQuery.departDate = leg.date
            legQuery.tripType = .oneWay
            let flights = await fetchSchedules(for: legQuery)
            output.append((leg: leg, flights: flights))
        }
        return output
    }

    static func sort(_ flights: [Flight], by filter: FlightSortFilter) -> [Flight] {
        switch filter {
        case .all: return flights
        case .cheapest: return flights.sorted { $0.priceUSD < $1.priceUSD }
        case .fastest: return flights.sorted { $0.durationMinutes < $1.durationMinutes }
        case .nonStop: return flights.filter { $0.stops == 0 }
        case .morning: return flights.filter { hour(from: $0.departure) < 12 }
        case .evening: return flights.filter { hour(from: $0.departure) >= 17 }
        }
    }

    private static func baseDuration(_ factor: Double) -> Int {
        Int(140 * factor)
    }

    private static func routeFactor(from: String, to: String) -> Double {
        let key = [from, to].sorted().joined()
        switch key {
        case _ where from == to: return 0.5
        case "DXBKHI", "DXBLHE", "ISBDXB", "KHIDXB", "LHEDXB": return 1.0
        case "KHILHE", "ISBKHI", "ISBLHE": return 0.75
        case _ where key.contains("LHR") || key.contains("JFK"): return 2.8
        case _ where key.contains("IST") || key.contains("DOH"): return 1.4
        default: return 1.2
        }
    }

    private static func dayOfWeekFactor(_ date: Date) -> Double {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 6 || weekday == 7 ? 1.12 : 1.0
    }

    private static func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func formatTime(hour: Int, minute: Int, addMinutes: Int = 0) -> String {
        var total = hour * 60 + minute + addMinutes
        while total >= 24 * 60 { total -= 24 * 60 }
        let h = total / 60
        let m = total % 60
        return String(format: "%02d:%02d", h, m)
    }

    private static func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func hour(from time: String) -> Int {
        Int(time.prefix(2)) ?? 0
    }

    // MARK: - Segment builder

    private static func buildSegments(
        primary: (name: String, code: String, econ: Int, biz: Int),
        from: Airport,
        to: Airport,
        departHour: Int,
        departMinute: Int,
        totalDurationMin: Int,
        stops: Int,
        seed: Int
    ) -> [FlightSegment] {
        if stops == 0 {
            return [makeSegment(
                carrier: primary,
                fromCode: from.code, fromCity: from.city,
                toCode: to.code, toCity: to.city,
                departHour: departHour, departMinute: departMinute,
                durationMin: totalDurationMin,
                layoverAfter: nil,
                flightOffset: seed % 900 + 100
            )]
        }

        let hub = hubAirport(from: from.code, to: to.code, seed: seed)
        var partnerCarrier = carriers[(seed + 2) % carriers.count]
        if partnerCarrier.code == primary.code {
            partnerCarrier = defaultPartner(for: primary.code)
        }

        if stops == 1 {
            let layover = 70 + (seed % 40)
            let leg1 = max(totalDurationMin / 2 - 10, 55)
            let leg2 = max(totalDurationMin - leg1 - layover, 50)
            let seg1 = makeSegment(
                carrier: primary,
                fromCode: from.code, fromCity: from.city,
                toCode: hub.code, toCity: hub.city,
                departHour: departHour, departMinute: departMinute,
                durationMin: leg1,
                layoverAfter: layover,
                flightOffset: seed % 900 + 100
            )
            let seg2Depart = minutesAfter(hour: departHour, minute: departMinute, add: leg1 + layover)
            let seg2 = makeSegment(
                carrier: partnerCarrier,
                fromCode: hub.code, fromCity: hub.city,
                toCode: to.code, toCity: to.city,
                departHour: seg2Depart.hour, departMinute: seg2Depart.minute,
                durationMin: leg2,
                layoverAfter: nil,
                flightOffset: seed % 900 + 300
            )
            return [seg1, seg2]
        }

        let hub2 = hubAirport(from: hub.code, to: to.code, seed: seed + 7)
        let carrier3 = carriers[(seed + 4) % carriers.count]
        let layover1 = 55 + (seed % 25)
        let layover2 = 60 + (seed % 30)
        let leg1 = max(totalDurationMin / 3, 50)
        let leg2 = max(totalDurationMin / 3, 45)
        let leg3 = max(totalDurationMin - leg1 - leg2 - layover1 - layover2, 40)

        let seg1 = makeSegment(
            carrier: primary,
            fromCode: from.code, fromCity: from.city,
            toCode: hub.code, toCity: hub.city,
            departHour: departHour, departMinute: departMinute,
            durationMin: leg1,
            layoverAfter: layover1,
            flightOffset: seed % 900 + 100
        )
        let seg2Depart = minutesAfter(hour: departHour, minute: departMinute, add: leg1 + layover1)
        let seg2 = makeSegment(
            carrier: partnerCarrier,
            fromCode: hub.code, fromCity: hub.city,
            toCode: hub2.code, toCity: hub2.city,
            departHour: seg2Depart.hour, departMinute: seg2Depart.minute,
            durationMin: leg2,
            layoverAfter: layover2,
            flightOffset: seed % 900 + 250
        )
        let seg3Depart = minutesAfter(
            hour: seg2Depart.hour, minute: seg2Depart.minute,
            add: leg2 + layover2
        )
        let seg3 = makeSegment(
            carrier: carrier3,
            fromCode: hub2.code, fromCity: hub2.city,
            toCode: to.code, toCity: to.city,
            departHour: seg3Depart.hour, departMinute: seg3Depart.minute,
            durationMin: leg3,
            layoverAfter: nil,
            flightOffset: seed % 900 + 400
        )
        return [seg1, seg2, seg3]
    }

    private static func makeSegment(
        carrier: (name: String, code: String, econ: Int, biz: Int),
        fromCode: String, fromCity: String,
        toCode: String, toCity: String,
        departHour: Int, departMinute: Int,
        durationMin: Int,
        layoverAfter: Int?,
        flightOffset: Int
    ) -> FlightSegment {
        FlightSegment(
            airline: carrier.name,
            iataCode: carrier.code,
            flightNumber: "\(carrier.code)\(flightOffset)",
            originCode: fromCode,
            originCity: fromCity,
            destinationCode: toCode,
            destinationCity: toCity,
            departure: formatTime(hour: departHour, minute: departMinute),
            arrival: formatTime(hour: departHour, minute: departMinute, addMinutes: durationMin),
            durationMinutes: durationMin,
            layoverMinutes: layoverAfter
        )
    }

    private static func hubAirport(from: String, to: String, seed: Int) -> Airport {
        let hubs = ["DOH", "IST", "AUH", "SHJ", "RUH", "SIN"]
        let preferred: [String]
        switch (from, to) {
        case ("KHI", _), (_, "KHI"), ("LHE", _), (_, "LHE"):
            preferred = ["DOH", "IST", "AUH", "SHJ"]
        case (_, "LHR"), ("LHR", _), (_, "JFK"), ("JFK", _):
            preferred = ["IST", "DOH", "AUH"]
        default:
            preferred = hubs
        }
        let code = preferred[seed % preferred.count]
        return AirportCatalog.all.first { $0.code == code }
            ?? Airport(code: code, city: code, country: "")
    }

    private static func defaultPartner(for code: String) -> (name: String, code: String, econ: Int, biz: Int) {
        switch code {
        case "EK", "FZ", "G9": return carriers.first { $0.code == "QR" } ?? carriers[4]
        case "QR": return carriers.first { $0.code == "TK" } ?? carriers[6]
        case "TK": return carriers.first { $0.code == "QR" } ?? carriers[4]
        default: return carriers.first { $0.code == "EK" } ?? carriers[0]
        }
    }

    private static func minutesAfter(hour: Int, minute: Int, add: Int) -> (hour: Int, minute: Int) {
        var total = hour * 60 + minute + add
        while total >= 24 * 60 { total -= 24 * 60 }
        return (total / 60, total % 60)
    }
}
