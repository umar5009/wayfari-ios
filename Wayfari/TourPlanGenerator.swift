import Foundation
import CoreLocation

// MARK: - Natural-language tour planner
enum TourPlanGenerator {

    // MARK: Public API

    /// Extracts whatever trip details are present (may be incomplete).
    static func extractPartial(from text: String) -> TourRequest {
        let lower = text.lowercased()
        let origin = OriginCatalog.matchOrigin(in: lower)
        let visitDestinations = matchVisitDestinations(in: lower, originCity: origin?.city)

        return TourRequest(
            destinations: visitDestinations,
            days: parseDays(from: lower),
            travelers: parseTravelers(from: lower),
            budgetHint: parseBudgetHint(from: lower),
            originCountry: origin?.country,
            originCity: origin?.city,
            rawQuery: text
        )
    }

    /// True when the message looks like the user wants a tour / package planned
    /// (vs a general Q&A like “is France safe?”).
    static func looksLikePlanningRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let destinations = matchVisitDestinations(in: lower, originCity: nil)
        let hasDuration = parseDays(from: lower) != nil

        let hasPlanIntent =
            lower.contains("plan") || lower.contains("tour") || lower.contains("trip") ||
            lower.contains("itinerary") || lower.contains("visit") || lower.contains("travel") ||
            lower.contains("holiday") || lower.contains("vacation") || lower.contains("package") ||
            lower.contains("overall") || lower.contains("suggest") || lower.contains("organize") ||
            lower.contains("organise") || lower.contains("give me") || lower.contains("show me") ||
            lower.contains("want to go") || lower.contains("going to") || lower.contains("book") ||
            lower.contains("days") || lower.contains("nights")

        let multiStop = destinations.count >= 2

        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).filter { !$0.isEmpty }
        let bareDestination = destinations.count == 1
            && tokens.count <= 3
            && !lower.hasPrefix("is ") && !lower.hasPrefix("are ") && !lower.hasPrefix("what")
            && !lower.hasPrefix("how") && !lower.hasPrefix("when") && !lower.hasPrefix("why")
            && !lower.contains("visa") && !lower.contains("weather") && !lower.contains("safe")
            && !lower.contains("food") && !lower.contains("currency")

        // Duration-only replies while clarifying (“7 days”, “10”)
        let durationOnly = hasDuration && destinations.isEmpty && tokens.count <= 4

        return hasDuration || hasPlanIntent || multiStop || bareDestination || durationOnly
    }

    /// Legacy helper — complete requests only.
    static func parseRequest(from text: String) -> TourRequest? {
        guard looksLikePlanningRequest(text) else { return nil }
        let partial = extractPartial(from: text)
        return partial.isComplete ? partial.resolved() : partial
    }

    static func generate(from request: TourRequest) -> TourPlan {
        guard let resolved = request.resolved() else {
            preconditionFailure("generate requires destination, days, and departure country")
        }
        let dayCount = resolved.days ?? 5
        let profile = DestinationCatalog.profile(for: resolved.destinations)
        let days = buildItinerary(request: resolved, profile: profile)
        let flights = buildFlights(request: resolved)
        let hotels = buildHotels(request: resolved, profile: profile)

        let hotelMid = hotels.first(where: { $0.stars == 4 })?.pricePerNight
            ?? hotels.first?.pricePerNight ?? 120
        let flightMid = flights.first(where: { $0.tier == .value })?.priceUSD
            ?? flights.first?.priceUSD ?? 500
        let tickets = days.reduce(0) { $0 + $1.dayTicketsTotal }
        let foodPerDay = profile.dailyFoodUSD
        let localTransport = profile.dailyTransportUSD * dayCount
        let nights = resolved.nights

        let minTotal = flightMid / 2
            + (hotels.first(where: { $0.stars == 3 })?.pricePerNight ?? 70) * nights
            + tickets / 2
            + foodPerDay * dayCount / 2
            + localTransport / 2
        let maxTotal = (flights.last?.priceUSD ?? flightMid * 3)
            + (hotels.first(where: { $0.stars == 5 })?.pricePerNight ?? hotelMid * 2) * nights
            + tickets
            + foodPerDay * dayCount
            + localTransport
            + 200

        let destLabel = resolved.destinations.joined(separator: " & ")
        let travelers = resolved.travelers ?? 2
        let summary = """
        A \(dayCount)-day tour of \(destLabel) for \(travelers) traveller\(travelers == 1 ? "" : "s"). \
        Below you’ll find cheapest-to-luxury flights, 3★–5★ hotels, a full day-by-day itinerary with attraction ticket prices, \
        a guided route map from home through each city and back, and practical tips so you can pick the mix that fits your style.
        """

        let routeStops = buildRouteStops(request: resolved, days: days, profile: profile)
        let placePins = buildPlacePins(days: days, destinations: resolved.destinations)

        return TourPlan(
            request: resolved,
            summary: summary,
            bestSeason: profile.bestSeason,
            currency: profile.currency,
            visaNote: profile.visaNote,
            estimatedBudgetMin: max(minTotal, 400),
            estimatedBudgetMax: max(maxTotal, minTotal + 500),
            flights: flights,
            hotels: hotels,
            days: days,
            routeStops: routeStops,
            placePins: placePins,
            tips: profile.tips
        )
    }

    static func clarificationMessage(for draft: TourRequest) -> String {
        let missing = draft.missingRequirements
        guard let first = missing.first else {
            return "I have everything I need — generating your plan now."
        }

        var known: [String] = []
        if !draft.destinations.isEmpty {
            known.append("destination: \(draft.destinations.joined(separator: " & "))")
        }
        if let days = draft.days {
            known.append("\(days) days")
        }
        if let travelers = draft.travelers {
            known.append("\(travelers) travellers")
        }
        if let originCountry = draft.originCountry {
            if let city = draft.originCity {
                known.append("departing from \(city), \(originCountry)")
            } else {
                known.append("departing from \(originCountry)")
            }
        }

        let knownPrefix = known.isEmpty
            ? "Happy to help plan your trip!"
            : "Got it so far — \(known.joined(separator: ", "))."

        // Ask only the next missing detail so answers don't get stuck in a loop.
        return "\(knownPrefix) \(first.prompt)"
    }

    static let dayQuickOptions = ["3 days", "5 days", "7 days", "10 days", "14 days"]

    // MARK: - Parsing helpers

    /// Prefer visit phrasing: "to X", "visit X", "tour of X", "X and Y",
    /// while ignoring departure cities like Lahore.
    private static func matchVisitDestinations(in lower: String, originCity: String?) -> [String] {
        var working = lower
        // Strip all departure clauses first so "from Canada to USA from Lahore"
        // does not keep a false Canada origin as a destination-only token.
        if let regex = try? NSRegularExpression(pattern: #"\b(from|departing from|flying from|leaving from)\s+([a-z .']+?)(?=\s+(to|and|for|,|\.|$))"#) {
            working = regex.stringByReplacingMatches(
                in: working,
                range: NSRange(working.startIndex..., in: working),
                withTemplate: " "
            )
        }
        if let city = originCity?.lowercased() {
            working = working.replacingOccurrences(of: city, with: " ")
        }
        // Keep "to Canada and USA" / "Canada and USA" / "visit France"
        return matchDestinations(in: working)
    }

    private static func destinationOnlyText(_ lower: String, excludingOriginCity: String?) -> String {
        var text = lower.replacingOccurrences(
            of: #"\b(from|departing from|flying from|leaving from)\s+.+?\s+to\s+"#,
            with: "to ",
            options: .regularExpression
        )
        if let city = excludingOriginCity?.lowercased() {
            text = text.replacingOccurrences(
                of: #"\b(from|departing from|flying from|leaving from)\s+\#(NSRegularExpression.escapedPattern(for: city))\b"#,
                with: " ",
                options: .regularExpression
            )
        }
        return text
    }

    static func matchDestinations(in lower: String) -> [String] {
        let text = OriginCatalog.normalizeMatchingText(lower)
        var found: [(range: Range<String.Index>, name: String)] = []
        // Longer aliases first so "south africa" wins over partial noise
        let catalog = DestinationCatalog.all.flatMap { entry in
            entry.aliases.map { (alias: $0, name: entry.displayName) }
        }.sorted { $0.alias.count > $1.alias.count }

        for entry in catalog {
            if let r = text.range(of: entry.alias) {
                // Avoid duplicate names
                if !found.contains(where: { $0.name == entry.name }) {
                    found.append((r, entry.name))
                }
            }
        }
        found.sort { $0.range.lowerBound < $1.range.lowerBound }
        var names: [String] = []
        for item in found where !names.contains(item.name) {
            names.append(item.name)
        }
        if names.count > 1, names.contains("Europe") {
            names.removeAll { $0 == "Europe" }
        }
        return Array(names.prefix(4))
    }

    /// Returns nil when duration was not mentioned — do not invent a default.
    static func parseDays(from lower: String) -> Int? {
        let patterns = [
            #"(\d+)\s*-?\s*days?"#,
            #"(\d+)\s*-?\s*nights?"#,
            #"for\s+(\d+)\s*days?"#,
            #"(\d+)\s*day\s*trip"#,
            #"spend\s+(\d+)"#,
            #"stay(?:ing)?\s+(\d+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: lower),
               let n = Int(lower[range]),
               (1...30).contains(n) {
                if lower.contains("night") && !lower.contains("day") {
                    return min(n + 1, 30)
                }
                return n
            }
        }
        if lower.contains("fortnight") { return 14 }
        if lower.contains("weekend") { return 3 }
        if lower.contains("two weeks") || lower.contains("2 weeks") { return 14 }
        if lower.contains("one week") || lower.contains("1 week") || lower.contains("a week") { return 7 }
        if lower.range(of: #"\bweek\b"#, options: .regularExpression) != nil { return 7 }

        // Bare number while clarifying days: “7”, “10”
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed), (1...30).contains(n) {
            return n
        }
        return nil
    }

    static func parseTravelers(from lower: String) -> Int? {
        let wordMap: [(String, Int)] = [
            ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5),
            ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10)
        ]
        if lower.contains("couple") || lower.contains("two of us") || lower.contains("just us two") { return 2 }
        if lower.contains("solo") || lower.contains("just me") || lower.contains("by myself") { return 1 }
        for (word, value) in wordMap {
            if lower.range(of: #"\b\#(word)\s+(people|persons|travellers?|travelers?|adults|of us|pax)\b"#,
                           options: .regularExpression) != nil {
                return value
            }
            if lower.range(of: #"\b(we are|we're|family of)\s+\#(word)\b"#,
                           options: .regularExpression) != nil {
                return value
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"family of\s+(\d+)"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let n = Int(lower[range]) { return n }
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*(people|persons|travellers?|travelers?|adults|pax)"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let n = Int(lower[range]), (1...12).contains(n) { return n }
        if lower.range(of: #"\bwe have\s+(\d+|five|four|three|two)\b"#, options: .regularExpression) != nil {
            if let regex = try? NSRegularExpression(pattern: #"we have\s+(\d+)"#),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let range = Range(match.range(at: 1), in: lower),
               let n = Int(lower[range]) { return n }
            for (word, value) in wordMap where lower.contains("we have \(word)") {
                return value
            }
        }
        // Loose phrasing: “…for 14 days with four of our group of people”.
        // Any people-word in the sentence lets us take the first count that isn’t a duration.
        if lower.range(of: #"\b(people|persons|travellers?|travelers?|adults|guests|members|of us|pax|group|family|friends)\b"#,
                       options: .regularExpression) != nil,
           let count = firstNonDurationCount(in: lower, wordMap: wordMap) {
            return count
        }
        return nil
    }

    /// First number in the sentence that isn't a duration (“14 days”, “2 weeks”).
    private static func firstNonDurationCount(in text: String, wordMap: [(String, Int)]) -> Int? {
        let numberWords = wordMap.map { $0.0 }.joined(separator: "|")
        let pattern = #"\b(\d{1,2}|\#(numberWords))\b(?:\s+(\w+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let excludedFollowers: Set<String> = [
            "day", "days", "night", "nights", "week", "weeks", "month", "months", "hour", "hours",
            "star", "stars", "country", "countries", "city", "cities", "place", "places",
            "stop", "stops", "hotel", "hotels", "flight", "flights", "am", "pm"
        ]

        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: text) else { continue }
            if match.range(at: 2).location != NSNotFound,
               let nextRange = Range(match.range(at: 2), in: text),
               excludedFollowers.contains(String(text[nextRange])) {
                continue
            }
            let token = String(text[numberRange])
            let value = Int(token) ?? wordMap.first(where: { $0.0 == token })?.1
            if let value, (1...12).contains(value) { return value }
        }
        return nil
    }

    static func parseBudgetHint(from lower: String) -> String? {
        if lower.contains("luxury") || lower.contains("5 star") || lower.contains("five star") { return "luxury" }
        if lower.contains("budget") || lower.contains("cheap") || lower.contains("3 star") { return "budget" }
        if lower.contains("mid") || lower.contains("4 star") { return "comfort" }
        return nil
    }

    // MARK: - Builders

    private static func buildFlights(request: TourRequest) -> [TourFlightOption] {
        let origins = OriginCatalog.airports(
            for: request.originCountry ?? "Pakistan",
            preferredCity: request.originCity
        )
        let destinationProfiles = DestinationCatalog.normalized(request.destinations)
            .map { DestinationCatalog.profile(for: [$0]) }

        return origins.flatMap { origin -> [TourFlightOption] in
            destinationProfiles.flatMap { destination -> [TourFlightOption] in
                let dest = destination.primaryAirport
                let route = "\(origin.code) → \(dest.code)"
                let base = Int(Double(destination.flightBaseUSD) * origin.priceMultiplier)
                return [
                    TourFlightOption(
                        tier: .budget, originCity: origin.city, originCode: origin.code,
                        airline: destination.budgetAirline.name, iataCode: destination.budgetAirline.code,
                        route: route, cabin: "Economy", duration: destination.flightDuration,
                        stops: "1–2 stops", departure: origin.budgetDeparture, arrival: destination.budgetArrival,
                        priceUSD: Int(Double(base) * 0.72),
                        notes: "To \(dest.city) · lowest fare · limited bags"
                    ),
                    TourFlightOption(
                        tier: .value, originCity: origin.city, originCode: origin.code,
                        airline: destination.valueAirline.name, iataCode: destination.valueAirline.code,
                        route: route, cabin: "Economy", duration: destination.flightDuration,
                        stops: destination.valueStops, departure: origin.valueDeparture, arrival: destination.valueArrival,
                        priceUSD: base,
                        notes: "To \(dest.city) · best balance of price & timing"
                    ),
                    TourFlightOption(
                        tier: .premium, originCity: origin.city, originCode: origin.code,
                        airline: destination.premiumAirline.name, iataCode: destination.premiumAirline.code,
                        route: route, cabin: "Premium Economy", duration: destination.flightDurationShort,
                        stops: "0–1 stop", departure: origin.premiumDeparture, arrival: destination.premiumArrival,
                        priceUSD: Int(Double(base) * 1.85),
                        notes: "To \(dest.city) · extra legroom & priority boarding"
                    ),
                    TourFlightOption(
                        tier: .luxury, originCity: origin.city, originCode: origin.code,
                        airline: destination.luxuryAirline.name, iataCode: destination.luxuryAirline.code,
                        route: route, cabin: "Business Class", duration: destination.flightDurationShort,
                        stops: "Non-stop / 1 stop", departure: origin.luxuryDeparture, arrival: destination.luxuryArrival,
                        priceUSD: Int(Double(base) * 3.4),
                        notes: "To \(dest.city) · lie-flat seats & lounge access"
                    ),
                ]
            }
        }
    }

    private static func buildHotels(request: TourRequest, profile: DestinationProfile) -> [TourHotelOption] {
        let countries = DestinationCatalog.normalized(request.destinations)
        let multiCity = countries.flatMap { DestinationCatalog.popularHotels(for: $0) }
        let combined = DestinationCatalog.expandedHotels(from: profile.hotels) + multiCity
        var seen = Set<String>()
        return combined.filter { hotel in
            let key = "\(hotel.name.lowercased())|\(hotel.city.lowercased())|\(hotel.stars)"
            return seen.insert(key).inserted
        }.sorted {
            if $0.stars != $1.stars { return $0.stars < $1.stars }
            if $0.city != $1.city { return $0.city < $1.city }
            return $0.pricePerNight < $1.pricePerNight
        }
    }

    private static func buildItinerary(request: TourRequest, profile: DestinationProfile) -> [ItineraryDay] {
        let templates = profile.itineraryTemplates
        guard !templates.isEmpty else { return [] }
        let dayCount = request.days ?? 1

        var days: [ItineraryDay] = []
        for i in 0..<dayCount {
            let t = templates[i % templates.count]
            let dayNum = i + 1
            var title = t.title
            var theme = t.theme
            var activities = t.activities

            if dayCount == 1 {
                title = "Full day · \(t.city)"
                theme = "Arrival, highlights & departure"
            } else if i == 0 {
                title = "Arrival · \(t.city)"
                theme = "Settle in & light exploring"
                // Lighter first day — keep morning/afternoon only when many activities
                if activities.count > 2 {
                    activities = Array(activities.prefix(2))
                }
            } else if i == dayCount - 1 {
                title = "Departure day · \(t.city)"
                theme = "Last highlights & airport"
                if activities.count > 2 {
                    activities = Array(activities.prefix(2))
                }
            }
            days.append(ItineraryDay(
                dayNumber: dayNum,
                title: title,
                city: t.city,
                theme: theme,
                activities: activities,
                mealsHint: t.mealsHint,
                transportHint: t.transportHint
            ))
        }
        return days
    }

    /// Home → first arrival city → unique internal itinerary cities → home.
    private static func buildRouteStops(
        request: TourRequest,
        days: [ItineraryDay],
        profile: DestinationProfile
    ) -> [TourRouteStop] {
        let homeCity = request.originCity
            ?? OriginCatalog.airports(for: request.originCountry ?? "Pakistan").first?.city
            ?? "Home"
        let homeCountry = request.originCountry ?? "Home"
        let homeCoord = CityCoordinates.coordinate(for: homeCity, country: homeCountry)

        var stops: [TourRouteStop] = []
        var order = 1

        stops.append(TourRouteStop(
            order: order,
            city: homeCity,
            country: homeCountry,
            kind: .departure,
            latitude: homeCoord.latitude,
            longitude: homeCoord.longitude,
            detail: "Start from home · international departure"
        ))
        order += 1

        // Unique itinerary cities in visit order
        var visited: [String] = []
        for day in days {
            let key = day.city.lowercased()
            if visited.contains(key) { continue }
            visited.append(key)
        }

        if visited.isEmpty {
            let arrivalCity = profile.primaryAirport.city
            let coord = CityCoordinates.coordinate(for: arrivalCity, country: profile.displayName)
            stops.append(TourRouteStop(
                order: order,
                city: arrivalCity,
                country: request.destinations.first ?? profile.displayName,
                kind: .arrival,
                latitude: coord.latitude,
                longitude: coord.longitude,
                detail: "International arrival"
            ))
            order += 1
        } else {
            for (index, city) in visited.enumerated() {
                let displayCity = days.first(where: { $0.city.lowercased() == city })?.city ?? city
                let country = countryForCity(displayCity, in: request.destinations) ?? (request.destinations.first ?? "")
                let coord = CityCoordinates.coordinate(for: displayCity, country: country)
                let kind: TourRouteStop.Kind = index == 0 ? .arrival : .internalStop
                let detail: String
                if index == 0 {
                    detail = "International arrival · begin tour"
                } else {
                    detail = "Internal transfer · city \(index) of \(max(visited.count - 1, 1))"
                }
                stops.append(TourRouteStop(
                    order: order,
                    city: displayCity,
                    country: country,
                    kind: kind,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    detail: detail
                ))
                order += 1
            }
        }

        stops.append(TourRouteStop(
            order: order,
            city: homeCity,
            country: homeCountry,
            kind: .returnHome,
            latitude: homeCoord.latitude,
            longitude: homeCoord.longitude,
            detail: "Return flight home"
        ))

        return stops
    }

    /// Every itinerary place with a map coordinate and ticket price (first visit only).
    private static func buildPlacePins(days: [ItineraryDay], destinations: [String]) -> [TourPlacePin] {
        var pins: [TourPlacePin] = []
        var seen = Set<String>()
        var perCityIndex: [String: Int] = [:]

        for day in days {
            let country = countryForCity(day.city, in: destinations) ?? (destinations.first ?? "")
            for activity in day.activities {
                let key = "\(day.city.lowercased())|\(activity.name.lowercased())"
                guard seen.insert(key).inserted else { continue }
                let cityKey = day.city.lowercased()
                let index = perCityIndex[cityKey] ?? 0
                perCityIndex[cityKey] = index + 1
                let coord = PlaceCoordinates.coordinate(
                    for: activity.name,
                    city: day.city,
                    country: country,
                    fallbackIndex: index
                )
                pins.append(TourPlacePin(
                    dayNumber: day.dayNumber,
                    name: activity.name,
                    city: day.city,
                    category: activity.category,
                    ticketPriceUSD: activity.ticketPriceUSD,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ))
            }
        }
        return pins
    }

    private static func countryForCity(_ city: String, in destinations: [String]) -> String? {
        let lower = city.lowercased()
        let cityCountryHints: [(String, String)] = [
            ("paris", "France"), ("versailles", "France"), ("lyon", "France"), ("nice", "France"),
            ("strasbourg", "France"), ("bordeaux", "France"),
            ("berlin", "Germany"), ("munich", "Germany"), ("hamburg", "Germany"), ("cologne", "Germany"),
            ("heidelberg", "Germany"), ("dresden", "Germany"), ("freiburg", "Germany"), ("frankfurt", "Germany"),
            ("toronto", "Canada"), ("vancouver", "Canada"), ("montreal", "Canada"), ("calgary", "Canada"),
            ("ottawa", "Canada"), ("niagara", "Canada"),
            ("new york", "United States"), ("los angeles", "United States"), ("chicago", "United States"),
            ("san francisco", "United States"), ("miami", "United States"), ("las vegas", "United States"),
            ("rome", "Italy"), ("florence", "Italy"), ("milan", "Italy"), ("venice", "Italy"),
            ("barcelona", "Spain"), ("madrid", "Spain"),
            ("london", "United Kingdom"), ("manchester", "United Kingdom"), ("edinburgh", "United Kingdom"),
            ("tokyo", "Japan"), ("kyoto", "Japan"), ("osaka", "Japan"),
            ("dubai", "UAE / Dubai"), ("abu dhabi", "UAE / Dubai"),
            ("zurich", "Switzerland"), ("interlaken", "Switzerland"),
            ("amsterdam", "Europe"), ("athens", "Greece"), ("istanbul", "Turkey"),
            ("bangkok", "Thailand"), ("singapore", "Singapore"), ("sydney", "Australia"),
        ]
        if let match = cityCountryHints.first(where: { lower.contains($0.0) })?.1,
           destinations.contains(match) || destinations.contains(where: { match.contains($0) || $0.contains(match) }) {
            return destinations.first(where: { $0 == match || match.contains($0) || $0.contains(match) }) ?? match
        }
        if let match = cityCountryHints.first(where: { lower.contains($0.0) })?.1 {
            return match
        }
        return destinations.first
    }
}

// MARK: - Destination catalogue

struct AirlineRef { let name: String; let code: String }
struct AirportRef { let code: String; let city: String }
struct OriginAirport {
    let city: String
    let code: String
    let priceMultiplier: Double
    let budgetDeparture: String
    let valueDeparture: String
    let premiumDeparture: String
    let luxuryDeparture: String
}

enum OriginCatalog {
    static let quickOptions = [
        "Lahore", "Karachi", "Islamabad", "Pakistan",
        "Delhi", "Mumbai", "India",
        "London", "United Kingdom",
        "New York", "United States",
        "Toronto", "Canada",
        "Dubai", "UAE",
        "Riyadh", "Saudi Arabia",
        "Sydney", "Australia"
    ]

    /// City aliases map to (display city, country). Prefer these over country-only matches.
    private static let cityAliases: [(city: String, country: String, aliases: [String])] = [
        ("Lahore", "Pakistan", ["lahore", "lhe"]),
        ("Karachi", "Pakistan", ["karachi", "khi"]),
        ("Islamabad", "Pakistan", ["islamabad", "isb", "rawalpindi"]),
        ("Peshawar", "Pakistan", ["peshawar", "pew"]),
        ("Sialkot", "Pakistan", ["sialkot", "skt"]),
        ("Multan", "Pakistan", ["multan", "mux"]),
        ("Delhi", "India", ["delhi", "new delhi", "del"]),
        ("Mumbai", "India", ["mumbai", "bombay", "bom"]),
        ("Bengaluru", "India", ["bengaluru", "bangalore", "blr"]),
        ("Chennai", "India", ["chennai", "madras", "maa"]),
        ("Hyderabad", "India", ["hyderabad", "hyd"]),
        ("Kolkata", "India", ["kolkata", "calcutta", "ccu"]),
        ("London", "United Kingdom", ["london", "lhr", "lgw", "stn"]),
        ("Manchester", "United Kingdom", ["manchester", "man"]),
        ("Birmingham", "United Kingdom", ["birmingham", "bhx"]),
        ("Edinburgh", "United Kingdom", ["edinburgh", "edi"]),
        ("New York", "United States", ["new york", "nyc", "jfk", "ewr"]),
        ("Los Angeles", "United States", ["los angeles", "lax"]),
        ("Chicago", "United States", ["chicago", "ord"]),
        ("Toronto", "Canada", ["toronto", "yyz"]),
        ("Vancouver", "Canada", ["vancouver", "yvr"]),
        ("Montreal", "Canada", ["montreal", "montréal", "yul"]),
        ("Dubai", "UAE", ["dubai", "dxb"]),
        ("Abu Dhabi", "UAE", ["abu dhabi", "auh"]),
        ("Riyadh", "Saudi Arabia", ["riyadh", "ruh"]),
        ("Jeddah", "Saudi Arabia", ["jeddah", "jed"]),
        ("Sydney", "Australia", ["sydney", "syd"]),
        ("Melbourne", "Australia", ["melbourne", "mel"]),
    ]

    private static let countryAliases: [(name: String, values: [String])] = [
        ("Pakistan", ["pakistan", "pk"]),
        ("India", ["india"]),
        ("United Kingdom", ["united kingdom", "uk", "england"]),
        ("United States", ["united states", "usa", "u.s.", "america"]),
        ("Canada", ["canada"]),
        ("UAE", ["uae"]),
        ("Saudi Arabia", ["saudi arabia", "ksa"]),
        ("Australia", ["australia"]),
    ]

    struct OriginMatch {
        let country: String
        let city: String?
        let score: Int // higher wins: city+from > city > country+from > country
        let position: Int
    }

    /// Resolves departure country/city. Prefer explicit cities like Lahore over
    /// destination countries that appear earlier in messy phrases like
    /// "tour from Canada to Canada and USA from Lahore".
    static func matchOrigin(in text: String) -> (country: String, city: String?)? {
        let lower = Self.normalizeMatchingText(text)
        var matches: [OriginMatch] = []

        for city in cityAliases {
            for alias in city.aliases {
                let fromPattern = #"\b(from|departing from|flying from|leaving from)\s+\#(NSRegularExpression.escapedPattern(for: alias))\b"#
                if let range = lower.range(of: fromPattern, options: .regularExpression) {
                    matches.append(OriginMatch(
                        country: city.country,
                        city: city.city,
                        score: 100,
                        position: lower.distance(from: lower.startIndex, to: range.lowerBound)
                    ))
                } else if let range = lower.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: alias))\b"#, options: .regularExpression) {
                    let windowStart = lower.index(range.lowerBound, offsetBy: -24, limitedBy: lower.startIndex) ?? lower.startIndex
                    let window = String(lower[windowStart..<range.upperBound])
                    if window.contains("from") || window.contains("depart") || window.contains("flying") || window.contains("leaving") {
                        matches.append(OriginMatch(
                            country: city.country,
                            city: city.city,
                            score: 80,
                            position: lower.distance(from: lower.startIndex, to: range.lowerBound)
                        ))
                    }
                }
            }
        }

        for country in countryAliases {
            for alias in country.values {
                let fromPattern = #"\b(from|departing from|flying from|leaving from)\s+\#(NSRegularExpression.escapedPattern(for: alias))\b"#
                if let range = lower.range(of: fromPattern, options: .regularExpression) {
                    matches.append(OriginMatch(
                        country: country.name,
                        city: nil,
                        score: 40,
                        position: lower.distance(from: lower.startIndex, to: range.lowerBound)
                    ))
                }
            }
        }

        // Clarification answers: bare "Pakistan", "Lahore", or "🇵🇰 Pakistan"
        if matches.isEmpty {
            if let bare = matchBareOriginAnswer(lower) {
                return bare
            }
        }

        guard let best = matches.max(by: {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.position < $1.position
        }) else { return nil }

        return (best.country, best.city)
    }

    /// Accepts short clarification replies without requiring the word "from".
    static func matchBareOriginAnswer(_ text: String) -> (country: String, city: String?)? {
        let lower = Self.normalizeMatchingText(text)
        let tokens = lower.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        guard tokens.count <= 4 else { return nil }

        for city in cityAliases {
            if city.aliases.contains(where: { lower == $0 || tokens.contains($0) })
                || lower == city.city.lowercased() {
                return (city.country, city.city)
            }
        }
        for country in countryAliases {
            if country.values.contains(where: { lower == $0 || tokens.contains($0) })
                || lower == country.name.lowercased() {
                return (country.name, nil)
            }
        }
        return nil
    }

    static func normalizeMatchingText(_ text: String) -> String {
        let lowered = text.lowercased()
        // Strip flag/emoji clusters so "🇵🇰 pakistan" → "pakistan"
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if scalar.properties.isEmojiPresentation || scalar.properties.generalCategory == .otherSymbol {
                return " "
            }
            if (0x1F1E6...0x1F1FF).contains(scalar.value) { // regional indicator (flags)
                return " "
            }
            return Character(scalar)
        }
        return String(scalars)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchCountry(in text: String, requireFromPrefix: Bool) -> String? {
        if requireFromPrefix {
            return matchOrigin(in: text)?.country
        }
        let lower = Self.normalizeMatchingText(text)
        if let origin = matchOrigin(in: lower) { return origin.country }
        if let bare = matchBareOriginAnswer(lower) { return bare.country }
        for city in cityAliases {
            if city.aliases.contains(where: { lower == $0 || lower.contains($0) }) {
                return city.country
            }
            if lower == city.city.lowercased() { return city.country }
        }
        for entry in countryAliases {
            for alias in entry.values where lower == alias || lower.contains(alias) {
                return entry.name
            }
        }
        return nil
    }

    static func airports(for country: String, preferredCity: String? = nil) -> [OriginAirport] {
        let values: [(String, String, Double)]
        switch country {
        case "India":
            values = [("Delhi", "DEL", 1.00), ("Mumbai", "BOM", 1.02), ("Bengaluru", "BLR", 1.05),
                      ("Chennai", "MAA", 1.06), ("Hyderabad", "HYD", 1.05), ("Kolkata", "CCU", 1.10)]
        case "United Kingdom":
            values = [("London", "LHR", 1.00), ("Manchester", "MAN", 1.06), ("Birmingham", "BHX", 1.08),
                      ("Edinburgh", "EDI", 1.10), ("Glasgow", "GLA", 1.11)]
        case "United States":
            values = [("New York", "JFK", 1.00), ("Los Angeles", "LAX", 1.07), ("Chicago", "ORD", 1.03),
                      ("San Francisco", "SFO", 1.08), ("Dallas", "DFW", 1.04), ("Miami", "MIA", 1.07)]
        case "Canada":
            values = [("Toronto", "YYZ", 1.00), ("Vancouver", "YVR", 1.06), ("Montreal", "YUL", 1.03),
                      ("Calgary", "YYC", 1.08), ("Ottawa", "YOW", 1.10)]
        case "UAE":
            values = [("Dubai", "DXB", 1.00), ("Abu Dhabi", "AUH", 1.02), ("Sharjah", "SHJ", 0.92)]
        case "Saudi Arabia":
            values = [("Riyadh", "RUH", 1.00), ("Jeddah", "JED", 1.00), ("Dammam", "DMM", 1.05),
                      ("Medina", "MED", 1.08)]
        case "Australia":
            values = [("Sydney", "SYD", 1.00), ("Melbourne", "MEL", 1.01), ("Brisbane", "BNE", 1.07),
                      ("Perth", "PER", 0.96), ("Adelaide", "ADL", 1.09)]
        default:
            values = [("Karachi", "KHI", 1.00), ("Lahore", "LHE", 1.03), ("Islamabad", "ISB", 1.04),
                      ("Peshawar", "PEW", 1.09), ("Sialkot", "SKT", 1.10), ("Multan", "MUX", 1.12)]
        }

        let times = [("02:40", "09:15", "11:00", "22:30"),
                     ("03:20", "08:45", "12:10", "21:50"),
                     ("04:10", "10:25", "13:00", "23:05")]
        var airports = values.enumerated().map { index, value in
            let time = times[index % times.count]
            return OriginAirport(
                city: value.0, code: value.1, priceMultiplier: value.2,
                budgetDeparture: time.0, valueDeparture: time.1,
                premiumDeparture: time.2, luxuryDeparture: time.3
            )
        }
        if let preferred = preferredCity {
            airports.sort {
                ($0.city.caseInsensitiveCompare(preferred) == .orderedSame ? 0 : 1)
                < ($1.city.caseInsensitiveCompare(preferred) == .orderedSame ? 0 : 1)
            }
        }
        return airports
    }
}

/// Approximate city coordinates for the itinerary route map.
enum CityCoordinates {
    static func coordinate(for city: String, country: String) -> CLLocationCoordinate2D {
        let key = city.lowercased()
        if let hit = table.first(where: { key.contains($0.0) || $0.0.contains(key) }) {
            return CLLocationCoordinate2D(latitude: hit.1, longitude: hit.2)
        }
        // Country fallbacks
        switch country {
        case "Pakistan": return CLLocationCoordinate2D(latitude: 31.5204, longitude: 74.3587) // Lahore
        case "India": return CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090)
        case "France": return CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        case "Germany": return CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
        case "Canada": return CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832)
        case "United States": return CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        case "United Kingdom": return CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        case "Japan": return CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        case "UAE", "UAE / Dubai": return CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708)
        case "Italy": return CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964)
        case "Spain": return CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
        case "Switzerland": return CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417)
        case "Australia": return CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        case "Thailand": return CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018)
        case "Turkey": return CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784)
        case "Singapore": return CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198)
        case "Greece": return CLLocationCoordinate2D(latitude: 37.9838, longitude: 23.7275)
        case "South Africa": return CLLocationCoordinate2D(latitude: -33.9249, longitude: 18.4241)
        default: return CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        }
    }

    private static let table: [(String, Double, Double)] = [
        ("lahore", 31.5204, 74.3587), ("karachi", 24.8607, 67.0011), ("islamabad", 33.6844, 73.0479),
        ("peshawar", 34.0151, 71.5249), ("multan", 30.1575, 71.5249), ("sialkot", 32.4945, 74.5229),
        ("delhi", 28.6139, 77.2090), ("mumbai", 19.0760, 72.8777), ("bengaluru", 12.9716, 77.5946),
        ("chennai", 13.0827, 80.2707), ("hyderabad", 17.3850, 78.4867), ("kolkata", 22.5726, 88.3639),
        ("london", 51.5074, -0.1278), ("manchester", 53.4808, -2.2426), ("edinburgh", 55.9533, -3.1883),
        ("birmingham", 52.4862, -1.8904), ("glasgow", 55.8642, -4.2518),
        ("new york", 40.7128, -74.0060), ("los angeles", 34.0522, -118.2437), ("chicago", 41.8781, -87.6298),
        ("san francisco", 37.7749, -122.4194), ("miami", 25.7617, -80.1918), ("dallas", 32.7767, -96.7970),
        ("las vegas", 36.1699, -115.1398),
        ("toronto", 43.6532, -79.3832), ("vancouver", 49.2827, -123.1207), ("montreal", 45.5017, -73.5673),
        ("calgary", 51.0447, -114.0719), ("ottawa", 45.4215, -75.6972), ("niagara", 43.0896, -79.0849),
        ("paris", 48.8566, 2.3522), ("versailles", 48.8049, 2.1204), ("lyon", 45.7640, 4.8357),
        ("nice", 43.7102, 7.2620), ("strasbourg", 48.5734, 7.7521), ("bordeaux", 44.8378, -0.5792),
        ("berlin", 52.5200, 13.4050), ("munich", 48.1351, 11.5820), ("hamburg", 53.5511, 9.9937),
        ("cologne", 50.9375, 6.9603), ("heidelberg", 49.3988, 8.6724), ("dresden", 51.0504, 13.7373),
        ("freiburg", 47.9990, 7.8421), ("frankfurt", 50.1109, 8.6821),
        ("rome", 41.9028, 12.4964), ("florence", 43.7696, 11.2558), ("milan", 45.4642, 9.1900),
        ("venice", 45.4408, 12.3155), ("barcelona", 41.3874, 2.1686), ("madrid", 40.4168, -3.7038),
        ("amsterdam", 52.3676, 4.9041), ("zurich", 47.3769, 8.5417), ("interlaken", 46.6863, 7.8632),
        ("tokyo", 35.6762, 139.6503), ("kyoto", 35.0116, 135.7681), ("osaka", 34.6937, 135.5023),
        ("dubai", 25.2048, 55.2708), ("abu dhabi", 24.4539, 54.3773), ("sharjah", 25.3463, 55.4209),
        ("bangkok", 13.7563, 100.5018), ("singapore", 1.3521, 103.8198), ("sydney", -33.8688, 151.2093),
        ("melbourne", -37.8136, 144.9631), ("istanbul", 41.0082, 28.9784), ("athens", 37.9838, 23.7275),
        ("marrakech", 31.6295, -7.9811), ("riyadh", 24.7136, 46.6753), ("jeddah", 21.4858, 39.1925),
        ("cape town", -33.9249, 18.4241), ("johannesburg", -26.2041, 28.0473), ("durban", -29.8587, 31.0218),
        ("kruger", -24.0, 31.5), ("stellenbosch", -33.9321, 18.8602),
    ]
}

/// Coordinates for individual attractions. Known landmarks are exact-ish; anything
/// else is spread deterministically around its city centre so pins never overlap.
enum PlaceCoordinates {
    static func coordinate(
        for place: String,
        city: String,
        country: String,
        fallbackIndex: Int
    ) -> CLLocationCoordinate2D {
        let key = place.lowercased()
        if let hit = landmarks.first(where: { key.contains($0.0) }) {
            return CLLocationCoordinate2D(latitude: hit.1, longitude: hit.2)
        }
        let base = CityCoordinates.coordinate(for: city, country: country)
        let angle = Double(fallbackIndex) * 2.399963 // golden angle keeps points apart
        let radius = 0.010 + Double(fallbackIndex) * 0.0035
        let lonScale = max(cos(base.latitude * .pi / 180), 0.25)
        return CLLocationCoordinate2D(
            latitude: base.latitude + radius * sin(angle),
            longitude: base.longitude + (radius / lonScale) * cos(angle)
        )
    }

    private static let landmarks: [(String, Double, Double)] = [
        // United States
        ("statue of liberty", 40.6892, -74.0445), ("central park", 40.7812, -73.9665),
        ("top of the rock", 40.7593, -73.9794), ("empire state", 40.7484, -73.9857),
        ("the met", 40.7794, -73.9632), ("moma", 40.7614, -73.9776),
        ("brooklyn bridge", 40.7061, -73.9969), ("times square", 40.7580, -73.9855),
        ("high line", 40.7480, -74.0048), ("9/11", 40.7115, -74.0134),
        ("golden gate", 37.8199, -122.4783), ("alcatraz", 37.8270, -122.4230),
        ("hollywood", 34.1341, -118.3215), ("santa monica", 34.0100, -118.4962),
        // Canada
        ("cn tower", 43.6426, -79.3871), ("ripley", 43.6424, -79.3860),
        ("distillery", 43.6503, -79.3596), ("harbourfront", 43.6387, -79.3816),
        ("niagara", 43.0828, -79.0742), ("hornblower", 43.0870, -79.0740),
        ("journey behind", 43.0805, -79.0784),
        ("stanley park", 49.3017, -123.1417), ("granville", 49.2713, -123.1345),
        ("old montreal", 45.5075, -73.5540),
        // France
        ("eiffel", 48.8584, 2.2945), ("louvre", 48.8606, 2.3376),
        ("seine", 48.8600, 2.2977), ("sacr", 48.8867, 2.3431),
        ("orsay", 48.8600, 2.3266), ("latin quarter", 48.8499, 2.3469),
        ("notre-dame", 48.8530, 2.3499), ("arc de triomphe", 48.8738, 2.2950),
        ("palace & hall of mirrors", 48.8049, 2.1204), ("marie antoinette", 48.8149, 2.1094),
        ("fourvi", 45.7623, 4.8226), ("vieux lyon", 45.7620, 4.8270),
        ("confluences", 45.7325, 4.8180),
        ("promenade des anglais", 43.6950, 7.2650), ("castle hill", 43.6950, 7.2790),
        ("strasbourg cathedral", 48.5819, 7.7509), ("petite france", 48.5800, 7.7420),
        ("miroir", 44.8412, -0.5695), ("du vin", 44.8628, -0.5500),
        // Germany
        ("brandenburg", 52.5163, 13.3777), ("museum island", 52.5169, 13.4019),
        ("east side gallery", 52.5050, 13.4394), ("checkpoint charlie", 52.5075, 13.3903),
        ("marienplatz", 48.1374, 11.5755), ("residenz", 48.1414, 11.5787),
        ("englischer garten", 48.1642, 11.6055),
        ("speicherstadt", 53.5433, 9.9925), ("elbphilharmonie", 53.5413, 9.9841),
        ("cologne cathedral", 50.9413, 6.9583), ("chocolate museum", 50.9320, 6.9640),
        ("heidelberg castle", 49.4106, 8.7150), ("philosophers", 49.4160, 8.7010),
        ("zwinger", 51.0530, 13.7337), ("brühl", 51.0540, 13.7400),
        ("münster", 47.9955, 7.8523), ("black forest", 47.9000, 8.1000),
        // Italy / Spain / Netherlands / UK
        ("colosseum", 41.8902, 12.4922), ("pantheon", 41.8986, 12.4769),
        ("trevi", 41.9009, 12.4833), ("vatican museums", 41.9065, 12.4536),
        ("st. peter", 41.9022, 12.4539), ("castel sant", 41.9031, 12.4663),
        ("uffizi", 43.7678, 11.2553), ("duomo", 43.7731, 11.2560),
        ("ponte vecchio", 43.7680, 11.2531),
        ("sagrada", 41.4036, 2.1744), ("park g", 41.4145, 2.1527),
        ("gothic quarter", 41.3833, 2.1769), ("prado", 40.4138, -3.6921),
        ("retiro", 40.4153, -3.6844), ("la latina", 40.4110, -3.7090),
        ("canal cruise", 52.3730, 4.8900), ("van gogh", 52.3584, 4.8811),
        ("jordaan", 52.3800, 4.8830),
        ("tower of london", 51.5081, -0.0759), ("british museum", 51.5194, -0.1270),
        ("westminster", 51.4995, -0.1248), ("london eye", 51.5033, -0.1196),
        // Asia / Middle East / Oceania / Africa
        ("burj khalifa", 25.1972, 55.2744), ("dubai mall", 25.1985, 55.2796),
        ("desert safari", 24.8000, 55.5500), ("palm jumeirah", 25.1124, 55.1390),
        ("sheikh zayed", 24.4128, 54.4750),
        ("senso", 35.7148, 139.7967), ("shibuya", 35.6595, 139.7005),
        ("meiji", 35.6764, 139.6993), ("fushimi", 34.9671, 135.7727),
        ("kinkaku", 35.0394, 135.7292), ("arashiyama", 35.0094, 135.6668),
        ("grand palace", 13.7500, 100.4913), ("wat arun", 13.7437, 100.4889),
        ("marina bay", 1.2834, 103.8607), ("gardens by the bay", 1.2816, 103.8636),
        ("sentosa", 1.2494, 103.8303),
        ("opera house", -33.8568, 151.2153), ("harbour bridge", -33.8523, 151.2108),
        ("bondi", -33.8915, 151.2767),
        ("table mountain", -33.9628, 18.4098), ("cape point", -34.3568, 18.4972),
        ("robben island", -33.8076, 18.3712), ("boulders", -34.1975, 18.4514),
        ("hagia sophia", 41.0086, 28.9802), ("blue mosque", 41.0054, 28.9768),
        ("acropolis", 37.9715, 23.7267),
    ]
}

struct DayTemplate {
    let city: String
    let title: String
    let theme: String
    let activities: [ItineraryActivity]
    let mealsHint: String
    let transportHint: String
}

struct DestinationProfile {
    let displayName: String
    let aliases: [String]
    let primaryAirport: AirportRef
    let currency: String
    let bestSeason: String
    let visaNote: String
    let flightBaseUSD: Int
    let flightDuration: String
    let flightDurationShort: String
    let budgetArrival: String
    let valueArrival: String
    let premiumArrival: String
    let luxuryArrival: String
    let valueStops: String
    let budgetAirline: AirlineRef
    let valueAirline: AirlineRef
    let premiumAirline: AirlineRef
    let luxuryAirline: AirlineRef
    let dailyFoodUSD: Int
    let dailyTransportUSD: Int
    let hotels: [TourHotelOption]
    let itineraryTemplates: [DayTemplate]
    let tips: [String]
}

enum DestinationCatalog {

    static func profile(for destinations: [String]) -> DestinationProfile {
        let strictNames = normalized(destinations)
        if strictNames.count >= 2 {
            return combinedProfile(strictNames)
        }
        let name = strictNames.first ?? "Europe"
        return all.first { $0.displayName == name } ?? europe
    }

    static func normalized(_ destinations: [String]) -> [String] {
        var names = destinations
        if names.count > 1 {
            names.removeAll { $0 == "Europe" }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    static var all: [DestinationProfile] {
        [europe, france, italy, spain, germany, unitedKingdom, switzerland,
         unitedStates, canada, japan, thailand, turkey, uae, maldives,
         australia, singapore, morocco, greece, southAfrica]
    }

    // Shared airline helpers
    private static let pia = AirlineRef(name: "Pakistan Int'l", code: "PK")
    private static let emirates = AirlineRef(name: "Emirates", code: "EK")
    private static let qatar = AirlineRef(name: "Qatar Airways", code: "QR")
    private static let turkish = AirlineRef(name: "Turkish Airlines", code: "TK")
    private static let etihad = AirlineRef(name: "Etihad", code: "EY")
    private static let lufthansa = AirlineRef(name: "Lufthansa", code: "LH")
    private static let british = AirlineRef(name: "British Airways", code: "BA")
    private static let airCanada = AirlineRef(name: "Air Canada", code: "AC")
    private static let delta = AirlineRef(name: "Delta", code: "DL")
    private static let ana = AirlineRef(name: "ANA", code: "NH")
    private static let singaporeAirlines = AirlineRef(name: "Singapore Airlines", code: "SQ")
    private static let thai = AirlineRef(name: "Thai Airways", code: "TG")
    private static let flydubai = AirlineRef(name: "flydubai", code: "FZ")

    // MARK: Strict multi-country composition
    // Only profiles explicitly requested are combined. No generic Europe templates
    // are injected, so France + Germany can never produce Rome or Barcelona.
    private static func combinedProfile(_ names: [String]) -> DestinationProfile {
        let joined = names.joined(separator: " & ")
        let profiles = names.compactMap { name in all.first { $0.displayName == name } }
        let first = profiles.first ?? europe
        let currencies = unique(profiles.map(\.currency)).joined(separator: " / ")
        let seasons = profiles.map { "\($0.displayName): \($0.bestSeason)" }.joined(separator: " · ")
        let visas = profiles.map { "\($0.displayName): \($0.visaNote)" }.joined(separator: " ")
        let hotels = profiles.flatMap(\.hotels)
        let itinerary = interleavedTemplates(from: profiles)
        let tips = unique(profiles.flatMap(\.tips))

        return DestinationProfile(
            displayName: joined,
            aliases: [],
            primaryAirport: first.primaryAirport,
            currency: currencies,
            bestSeason: seasons,
            visaNote: visas,
            flightBaseUSD: Int(Double(first.flightBaseUSD) * 1.15),
            flightDuration: first.flightDuration,
            flightDurationShort: first.flightDurationShort,
            budgetArrival: first.budgetArrival,
            valueArrival: first.valueArrival,
            premiumArrival: first.premiumArrival,
            luxuryArrival: first.luxuryArrival,
            valueStops: first.valueStops,
            budgetAirline: first.budgetAirline,
            valueAirline: first.valueAirline,
            premiumAirline: first.premiumAirline,
            luxuryAirline: first.luxuryAirline,
            dailyFoodUSD: profiles.map(\.dailyFoodUSD).max() ?? first.dailyFoodUSD,
            dailyTransportUSD: profiles.map(\.dailyTransportUSD).max() ?? first.dailyTransportUSD,
            hotels: hotels,
            itineraryTemplates: itinerary,
            tips: tips + ["Use an open-jaw flight: arrive in \(names.first ?? "the first country") and depart from \(names.last ?? "the final country") to avoid backtracking."]
        )
    }

    private static func interleavedTemplates(from profiles: [DestinationProfile]) -> [DayTemplate] {
        let maxCount = profiles.map { $0.itineraryTemplates.count }.max() ?? 0
        var result: [DayTemplate] = []
        for index in 0..<maxCount {
            for profile in profiles where index < profile.itineraryTemplates.count {
                result.append(profile.itineraryTemplates[index])
            }
        }
        return result
    }

    static func expandedHotels(from hotels: [TourHotelOption]) -> [TourHotelOption] {
        hotels.flatMap { hotel in
            let names = hotel.name.components(separatedBy: " / ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let cities = hotel.city.components(separatedBy: " / ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let neighbourhoods = hotel.neighbourhood.components(separatedBy: " / ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return names.enumerated().map { index, name in
                TourHotelOption(
                    name: name,
                    city: cities.indices.contains(index) ? cities[index] : (cities.first ?? hotel.city),
                    neighbourhood: neighbourhoods.indices.contains(index)
                        ? neighbourhoods[index]
                        : (neighbourhoods.first ?? hotel.neighbourhood),
                    stars: hotel.stars,
                    rating: max(7.0, hotel.rating - Double(index) * 0.1),
                    pricePerNight: max(30, hotel.pricePerNight + index * 18),
                    amenities: hotel.amenities,
                    style: hotel.style
                )
            }
        }
    }

    /// Hotels across popular cities for each requested country — not just one capital.
    static func popularHotels(for country: String) -> [TourHotelOption] {
        switch country {
        case "Canada":
            return [
                TourHotelOption(name: "Holiday Inn Express Downtown", city: "Toronto", neighbourhood: "Downtown", stars: 3, rating: 8.1, pricePerNight: 110, amenities: ["WiFi", "Breakfast", "Pool"], style: "Central Toronto value"),
                TourHotelOption(name: "Chelsea Hotel Toronto", city: "Toronto", neighbourhood: "Downtown", stars: 3, rating: 8.0, pricePerNight: 125, amenities: ["WiFi", "Family rooms", "Pool"], style: "Family-friendly Toronto"),
                TourHotelOption(name: "Marriott City Centre", city: "Toronto", neighbourhood: "Financial District", stars: 4, rating: 8.8, pricePerNight: 220, amenities: ["Gym", "Restaurant", "Views"], style: "Business comfort"),
                TourHotelOption(name: "Fairmont Royal York", city: "Toronto", neighbourhood: "Union Station", stars: 5, rating: 9.2, pricePerNight: 390, amenities: ["Spa", "Heritage", "Dining"], style: "Iconic Toronto luxury"),
                TourHotelOption(name: "Four Seasons Toronto", city: "Toronto", neighbourhood: "Yorkville", stars: 5, rating: 9.4, pricePerNight: 480, amenities: ["Spa", "Fine dining", "Concierge"], style: "Yorkville luxury"),

                TourHotelOption(name: "Days Inn Vancouver Downtown", city: "Vancouver", neighbourhood: "Downtown", stars: 3, rating: 8.0, pricePerNight: 130, amenities: ["WiFi", "Breakfast"], style: "Walkable Vancouver value"),
                TourHotelOption(name: "Pinnacle Hotel Harbourfront", city: "Vancouver", neighbourhood: "Coal Harbour", stars: 4, rating: 8.7, pricePerNight: 240, amenities: ["Harbour view", "Gym", "Pool"], style: "Waterfront comfort"),
                TourHotelOption(name: "Fairmont Hotel Vancouver", city: "Vancouver", neighbourhood: "Downtown", stars: 5, rating: 9.3, pricePerNight: 420, amenities: ["Spa", "Heritage", "Dining"], style: "Landmark luxury"),

                TourHotelOption(name: "Hotel Bonaventure Montreal", city: "Montreal", neighbourhood: "Downtown", stars: 3, rating: 8.2, pricePerNight: 115, amenities: ["Pool", "WiFi", "Metro"], style: "Central Montreal value"),
                TourHotelOption(name: "Hotel Place d'Armes", city: "Montreal", neighbourhood: "Old Montreal", stars: 4, rating: 8.9, pricePerNight: 230, amenities: ["Rooftop", "Spa", "Historic"], style: "Old-port boutique"),
                TourHotelOption(name: "Ritz-Carlton Montreal", city: "Montreal", neighbourhood: "Golden Square Mile", stars: 5, rating: 9.4, pricePerNight: 450, amenities: ["Spa", "Fine dining", "Concierge"], style: "Classic luxury"),

                TourHotelOption(name: "Hotel Arts Calgary", city: "Calgary", neighbourhood: "Beltline", stars: 4, rating: 8.6, pricePerNight: 190, amenities: ["Pool", "Restaurant", "Gym"], style: "Modern Calgary stay"),
                TourHotelOption(name: "Fairmont Chateau Laurier", city: "Ottawa", neighbourhood: "ByWard Market", stars: 5, rating: 9.1, pricePerNight: 360, amenities: ["Heritage", "Spa", "Dining"], style: "Capital landmark"),
            ]
        case "United States":
            return [
                TourHotelOption(name: "Pod 51", city: "New York", neighbourhood: "Midtown East", stars: 3, rating: 8.0, pricePerNight: 145, amenities: ["WiFi", "Compact", "Central"], style: "Smart NYC budget"),
                TourHotelOption(name: "Freehand New York", city: "New York", neighbourhood: "Flatiron", stars: 3, rating: 8.1, pricePerNight: 160, amenities: ["Rooftop", "WiFi", "Bar"], style: "Social Midtown stay"),
                TourHotelOption(name: "Hilton Midtown", city: "New York", neighbourhood: "Midtown", stars: 4, rating: 8.6, pricePerNight: 280, amenities: ["Gym", "Restaurant", "Central"], style: "Full-service 4★"),
                TourHotelOption(name: "The Plaza", city: "New York", neighbourhood: "5th Avenue", stars: 5, rating: 9.4, pricePerNight: 750, amenities: ["Iconic", "Spa", "Concierge"], style: "Landmark luxury"),

                TourHotelOption(name: "Freehand Los Angeles", city: "Los Angeles", neighbourhood: "Downtown", stars: 3, rating: 8.0, pricePerNight: 155, amenities: ["Pool", "WiFi", "Bar"], style: "DTLA value"),
                TourHotelOption(name: "Hotel Figueroa", city: "Los Angeles", neighbourhood: "Downtown", stars: 4, rating: 8.7, pricePerNight: 250, amenities: ["Pool", "Restaurant", "Design"], style: "Design comfort"),
                TourHotelOption(name: "The Beverly Hills Hotel", city: "Los Angeles", neighbourhood: "Beverly Hills", stars: 5, rating: 9.5, pricePerNight: 820, amenities: ["Pool", "Spa", "Iconic"], style: "Classic LA luxury"),

                TourHotelOption(name: "Freehand Chicago", city: "Chicago", neighbourhood: "River North", stars: 3, rating: 8.1, pricePerNight: 140, amenities: ["WiFi", "Bar", "Central"], style: "River North value"),
                TourHotelOption(name: "LondonHouse Chicago", city: "Chicago", neighbourhood: "The Loop", stars: 4, rating: 8.8, pricePerNight: 260, amenities: ["Rooftop", "River view", "Gym"], style: "Loop comfort"),
                TourHotelOption(name: "The Peninsula Chicago", city: "Chicago", neighbourhood: "Magnificent Mile", stars: 5, rating: 9.5, pricePerNight: 680, amenities: ["Spa", "Pool", "Dining"], style: "Michigan Ave luxury"),

                TourHotelOption(name: "Hotel Via", city: "San Francisco", neighbourhood: "SoMa", stars: 4, rating: 8.7, pricePerNight: 270, amenities: ["Rooftop", "Gym", "Views"], style: "Modern SF stay"),
                TourHotelOption(name: "The Ritz-Carlton San Francisco", city: "San Francisco", neighbourhood: "Nob Hill", stars: 5, rating: 9.3, pricePerNight: 620, amenities: ["Spa", "Concierge", "Dining"], style: "Nob Hill luxury"),
                TourHotelOption(name: "Freehand Miami", city: "Miami", neighbourhood: "Downtown", stars: 3, rating: 8.0, pricePerNight: 150, amenities: ["Pool", "WiFi", "Bar"], style: "Downtown Miami value"),
                TourHotelOption(name: "1 Hotel South Beach", city: "Miami", neighbourhood: "South Beach", stars: 5, rating: 9.2, pricePerNight: 540, amenities: ["Beach", "Spa", "Sustainable"], style: "Beach luxury"),
            ]
        case "France":
            return [
                TourHotelOption(name: "ibis Paris Bastille", city: "Paris", neighbourhood: "Bastille", stars: 3, rating: 8.0, pricePerNight: 95, amenities: ["WiFi", "Metro", "Breakfast"], style: "Central Paris value"),
                TourHotelOption(name: "Hôtel Le Six", city: "Paris", neighbourhood: "St-Germain", stars: 4, rating: 8.8, pricePerNight: 195, amenities: ["Design", "Bar", "Concierge"], style: "Boutique Left Bank"),
                TourHotelOption(name: "Shangri-La Paris", city: "Paris", neighbourhood: "Trocadéro", stars: 5, rating: 9.4, pricePerNight: 840, amenities: ["Eiffel view", "Pool", "Spa"], style: "Palace luxury"),
                TourHotelOption(name: "Hotel des Arts", city: "Lyon", neighbourhood: "Presqu'île", stars: 3, rating: 8.2, pricePerNight: 90, amenities: ["WiFi", "Metro"], style: "Central Lyon value"),
                TourHotelOption(name: "InterContinental Lyon", city: "Lyon", neighbourhood: "Bellecour", stars: 5, rating: 9.2, pricePerNight: 380, amenities: ["Spa", "Dining", "Heritage"], style: "Grand Lyon luxury"),
                TourHotelOption(name: "Hotel Windsor", city: "Nice", neighbourhood: "Promenade", stars: 4, rating: 8.6, pricePerNight: 180, amenities: ["Rooftop", "Sea view"], style: "Riviera comfort"),
                TourHotelOption(name: "Hotel Negresco", city: "Nice", neighbourhood: "Promenade des Anglais", stars: 5, rating: 9.1, pricePerNight: 420, amenities: ["Iconic", "Dining", "Sea view"], style: "Riviera landmark"),
                TourHotelOption(name: "Hôtel Cour du Corbeau", city: "Strasbourg", neighbourhood: "Petite France", stars: 4, rating: 8.9, pricePerNight: 170, amenities: ["Historic", "Breakfast"], style: "Alsace boutique"),
                TourHotelOption(name: "Hotel Burdigala", city: "Bordeaux", neighbourhood: "Centre", stars: 4, rating: 8.7, pricePerNight: 175, amenities: ["Spa", "Restaurant"], style: "Wine-city comfort"),
            ]
        case "Germany":
            return [
                TourHotelOption(name: "Motel One Alexanderplatz", city: "Berlin", neighbourhood: "Mitte", stars: 3, rating: 8.5, pricePerNight: 105, amenities: ["WiFi", "Bar", "U-Bahn"], style: "Modern Berlin value"),
                TourHotelOption(name: "25hours Bikini Berlin", city: "Berlin", neighbourhood: "Charlottenburg", stars: 4, rating: 8.8, pricePerNight: 195, amenities: ["Rooftop", "Sauna", "Design"], style: "Design comfort"),
                TourHotelOption(name: "Hotel Adlon Kempinski", city: "Berlin", neighbourhood: "Unter den Linden", stars: 5, rating: 9.5, pricePerNight: 420, amenities: ["Spa", "Historic", "Fine dining"], style: "Landmark luxury"),
                TourHotelOption(name: "Meininger Munich City Center", city: "Munich", neighbourhood: "Centre", stars: 3, rating: 8.1, pricePerNight: 100, amenities: ["WiFi", "Bar"], style: "Central Munich value"),
                TourHotelOption(name: "Hotel Bayerischer Hof", city: "Munich", neighbourhood: "Promenadeplatz", stars: 5, rating: 9.3, pricePerNight: 480, amenities: ["Spa", "Pool", "Dining"], style: "Bavarian luxury"),
                TourHotelOption(name: "Empire Riverside Hotel", city: "Hamburg", neighbourhood: "Harbour", stars: 4, rating: 8.7, pricePerNight: 185, amenities: ["River view", "Gym"], style: "Harbour comfort"),
                TourHotelOption(name: "Excelsior Hotel Ernst", city: "Cologne", neighbourhood: "Cathedral", stars: 5, rating: 9.2, pricePerNight: 360, amenities: ["Cathedral view", "Spa", "Dining"], style: "Rhine luxury"),
                TourHotelOption(name: "Hotel Europäischer Hof", city: "Heidelberg", neighbourhood: "Old Town", stars: 5, rating: 9.1, pricePerNight: 310, amenities: ["Spa", "Castle views"], style: "Romantic Heidelberg"),
                TourHotelOption(name: "Hotel Taschenbergpalais", city: "Dresden", neighbourhood: "Altstadt", stars: 5, rating: 9.2, pricePerNight: 340, amenities: ["Palace", "Spa", "Dining"], style: "Baroque luxury"),
            ]
        case "United Kingdom":
            return [
                TourHotelOption(name: "Premier Inn London County Hall", city: "London", neighbourhood: "South Bank", stars: 3, rating: 8.2, pricePerNight: 140, amenities: ["WiFi", "Breakfast", "Tube"], style: "Central London value"),
                TourHotelOption(name: "Hilton London Bankside", city: "London", neighbourhood: "South Bank", stars: 4, rating: 8.7, pricePerNight: 250, amenities: ["Gym", "River views"], style: "Modern 4★"),
                TourHotelOption(name: "The Savoy", city: "London", neighbourhood: "Strand", stars: 5, rating: 9.6, pricePerNight: 780, amenities: ["Afternoon tea", "Spa"], style: "Heritage luxury"),
                TourHotelOption(name: "Hotel Indigo Manchester", city: "Manchester", neighbourhood: "City Centre", stars: 4, rating: 8.6, pricePerNight: 160, amenities: ["Design", "Bar"], style: "Northern comfort"),
                TourHotelOption(name: "The Balmoral", city: "Edinburgh", neighbourhood: "Princes Street", stars: 5, rating: 9.4, pricePerNight: 420, amenities: ["Castle views", "Spa"], style: "Scottish landmark"),
            ]
        case "Japan":
            return [
                TourHotelOption(name: "APA Hotel Shinjuku", city: "Tokyo", neighbourhood: "Shinjuku", stars: 3, rating: 8.0, pricePerNight: 85, amenities: ["WiFi", "Station"], style: "Efficient Tokyo stay"),
                TourHotelOption(name: "Mitsui Garden Ginza", city: "Tokyo", neighbourhood: "Ginza", stars: 4, rating: 8.7, pricePerNight: 180, amenities: ["Onsen bath", "Views"], style: "Polished Ginza"),
                TourHotelOption(name: "Park Hyatt Tokyo", city: "Tokyo", neighbourhood: "Shinjuku", stars: 5, rating: 9.6, pricePerNight: 650, amenities: ["Sky bar", "Spa"], style: "Ultra luxury"),
                TourHotelOption(name: "Hotel Gracery Kyoto Sanjo", city: "Kyoto", neighbourhood: "Downtown", stars: 4, rating: 8.6, pricePerNight: 160, amenities: ["WiFi", "Central"], style: "Walkable Kyoto"),
                TourHotelOption(name: "The Ritz-Carlton Kyoto", city: "Kyoto", neighbourhood: "Kamogawa", stars: 5, rating: 9.5, pricePerNight: 700, amenities: ["River view", "Spa"], style: "Kyoto luxury"),
                TourHotelOption(name: "Cross Hotel Osaka", city: "Osaka", neighbourhood: "Namba", stars: 4, rating: 8.5, pricePerNight: 150, amenities: ["Food district", "Design"], style: "Namba comfort"),
            ]
        case "UAE / Dubai", "UAE":
            return [
                TourHotelOption(name: "ibis Al Barsha", city: "Dubai", neighbourhood: "Al Barsha", stars: 3, rating: 8.4, pricePerNight: 67, amenities: ["Metro", "Pool"], style: "Best-value Dubai"),
                TourHotelOption(name: "JW Marriott Marquis", city: "Dubai", neighbourhood: "Business Bay", stars: 4, rating: 9.1, pricePerNight: 145, amenities: ["Spa", "Pool", "Views"], style: "Tall comfort"),
                TourHotelOption(name: "Atlantis The Palm", city: "Dubai", neighbourhood: "Palm Jumeirah", stars: 5, rating: 9.5, pricePerNight: 320, amenities: ["Beach", "Waterpark"], style: "Palm luxury"),
                TourHotelOption(name: "Burj Al Arab", city: "Dubai", neighbourhood: "Jumeirah", stars: 5, rating: 9.7, pricePerNight: 900, amenities: ["Butler", "Helipad"], style: "Iconic luxury"),
                TourHotelOption(name: "Emirates Palace Mandarin Oriental", city: "Abu Dhabi", neighbourhood: "Corniche", stars: 5, rating: 9.4, pricePerNight: 480, amenities: ["Beach", "Palace", "Spa"], style: "Capital luxury"),
                TourHotelOption(name: "Hilton Abu Dhabi", city: "Abu Dhabi", neighbourhood: "Corniche", stars: 4, rating: 8.7, pricePerNight: 160, amenities: ["Beach", "Pool"], style: "Corniche comfort"),
            ]
        case "South Africa":
            return [
                TourHotelOption(name: "City Lodge Hotel Sandton", city: "Johannesburg", neighbourhood: "Sandton", stars: 3, rating: 8.1, pricePerNight: 95, amenities: ["WiFi", "Breakfast", "Pool"], style: "Business-district value"),
                TourHotelOption(name: "Radisson Blu Sandton", city: "Johannesburg", neighbourhood: "Sandton", stars: 4, rating: 8.6, pricePerNight: 160, amenities: ["Gym", "Restaurant", "Pool"], style: "Sandton comfort"),
                TourHotelOption(name: "Saxon Hotel", city: "Johannesburg", neighbourhood: "Sandhurst", stars: 5, rating: 9.4, pricePerNight: 420, amenities: ["Spa", "Garden", "Fine dining"], style: "Johannesburg luxury"),
                TourHotelOption(name: "The Capital Mirage", city: "Cape Town", neighbourhood: "City Centre", stars: 3, rating: 8.2, pricePerNight: 110, amenities: ["WiFi", "Breakfast"], style: "Central Cape Town value"),
                TourHotelOption(name: "Victoria & Alfred Hotel", city: "Cape Town", neighbourhood: "V&A Waterfront", stars: 4, rating: 8.8, pricePerNight: 200, amenities: ["Harbour view", "Restaurant"], style: "Waterfront comfort"),
                TourHotelOption(name: "One&Only Cape Town", city: "Cape Town", neighbourhood: "Waterfront", stars: 5, rating: 9.6, pricePerNight: 520, amenities: ["Spa", "Marina", "Fine dining"], style: "Iconic Cape luxury"),
                TourHotelOption(name: "Protea Hotel Fire & Ice!", city: "Durban", neighbourhood: "Umhlanga", stars: 3, rating: 8.0, pricePerNight: 100, amenities: ["Pool", "WiFi"], style: "Coastal value"),
                TourHotelOption(name: "Kruger lodge tented suite", city: "Kruger", neighbourhood: "Reserve", stars: 4, rating: 9.0, pricePerNight: 280, amenities: ["Game drives", "Full board"], style: "Safari comfort"),
                TourHotelOption(name: "Singita-style luxury lodge", city: "Kruger", neighbourhood: "Private reserve", stars: 5, rating: 9.7, pricePerNight: 900, amenities: ["Private guide", "Spa", "Full board"], style: "Ultra safari luxury"),
            ]
        default:
            return []
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func naMultiDays(_ names: [String]) -> [DayTemplate] {
        var days: [DayTemplate] = [
            DayTemplate(city: "Toronto", title: "Toronto highlights", theme: "Skyline & waterfront",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "CN Tower", category: "Landmark", detail: "EdgeWalk optional; book timed entry.", ticketPriceUSD: 43, durationHours: 2, tip: "Go early to skip queues."),
                            ItineraryActivity(time: "13:00", name: "Harbourfront & Distillery District", category: "Neighbourhood", detail: "Brick cobbles, cafés, galleries.", ticketPriceUSD: 0, durationHours: 3, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Ripley's Aquarium", category: "Attraction", detail: "Underwater tunnel & shark lagoon.", ticketPriceUSD: 40, durationHours: 2, tip: "Combo tickets save ~15%."),
                        ],
                        mealsHint: "Dinner in Kensington Market (~$25–40 pp)", transportHint: "TTC day pass ~$13"),
            DayTemplate(city: "Niagara", title: "Niagara Falls day trip", theme: "Nature spectacle",
                        activities: [
                            ItineraryActivity(time: "08:30", name: "Coach / train to Niagara", category: "Transfer", detail: "2 hours each way from Toronto.", ticketPriceUSD: 35, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "11:00", name: "Hornblower boat", category: "Experience", detail: "Ride into the mist at the Falls.", ticketPriceUSD: 32, durationHours: 1.5, tip: "Ponchos included."),
                            ItineraryActivity(time: "14:00", name: "Journey Behind the Falls", category: "Attraction", detail: "Tunnels & observation decks.", ticketPriceUSD: 22, durationHours: 1.5, tip: nil),
                        ],
                        mealsHint: "Lunch overlooking the Falls (~$30 pp)", transportHint: "Return coach included in many tours"),
        ]
        if names.contains("United States") {
            days += [
                DayTemplate(city: "New York", title: "Manhattan icons", theme: "Skyline & museums",
                            activities: [
                                ItineraryActivity(time: "09:00", name: "Statue of Liberty & Ellis Island", category: "Landmark", detail: "Ferry + pedestal or crown options.", ticketPriceUSD: 28, durationHours: 3.5, tip: "Security lines — arrive early."),
                                ItineraryActivity(time: "14:00", name: "Central Park & 5th Ave", category: "Walk", detail: "Bethesda Fountain, shopping window-gaze.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                                ItineraryActivity(time: "18:30", name: "TOP OF THE ROCK or Empire State", category: "Viewpoint", detail: "Sunset skyline views.", ticketPriceUSD: 44, durationHours: 1.5, tip: "Sunset slots sell out."),
                            ],
                            mealsHint: "Food-hall dinner in Chelsea Market (~$20–35)", transportHint: "Metro 7-day pass or OMNY pay-as-you-go"),
                DayTemplate(city: "New York", title: "Culture & neighbourhoods", theme: "Art & boroughs",
                            activities: [
                                ItineraryActivity(time: "10:00", name: "The Met or MoMA", category: "Museum", detail: "World-class permanent collections.", ticketPriceUSD: 30, durationHours: 3, tip: "Met suggests $30; pay-what-you-wish for NY residents only."),
                                ItineraryActivity(time: "14:30", name: "Brooklyn Bridge walk", category: "Walk", detail: "Cross to DUMBO for bridge photos.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                                ItineraryActivity(time: "17:30", name: "Times Square & Broadway show", category: "Entertainment", detail: "TKTS booth for same-day deals.", ticketPriceUSD: 89, durationHours: 3, tip: "Matinees Wed/Sat are cheaper."),
                            ],
                            mealsHint: "Pre-theatre prix fixe (~$45–70)", transportHint: "Walk + subway"),
            ]
        }
        return days
    }

    private static func europeCircuitDays(countHint: [String]) -> [DayTemplate] {
        var days = europe.itineraryTemplates
        if countHint.contains("Italy") || countHint.contains("Europe") {
            days += italy.itineraryTemplates.prefix(2)
        }
        if countHint.contains("Switzerland") {
            days += switzerland.itineraryTemplates.prefix(2)
        }
        return days
    }

    // MARK: Individual destinations

    static let europe = DestinationProfile(
        displayName: "Europe",
        aliases: ["europe", "european", "schengen", "eu trip"],
        primaryAirport: AirportRef(code: "CDG", city: "Paris"),
        currency: "EUR (€)",
        bestSeason: "May–Jun & Sep–Oct",
        visaNote: "One Schengen visa covers 29 countries. Apply via the embassy of your main stay.",
        flightBaseUSD: 690,
        flightDuration: "12–16h",
        flightDurationShort: "10–13h",
        budgetArrival: "19:10+1",
        valueArrival: "14:25+1",
        premiumArrival: "12:50+1",
        luxuryArrival: "07:05+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: lufthansa,
        luxuryAirline: emirates,
        dailyFoodUSD: 45,
        dailyTransportUSD: 18,
        hotels: [
            TourHotelOption(name: "Ibis Styles / Generator Hostel+", city: "Paris / multi-city", neighbourhood: "Central", stars: 3, rating: 8.1, pricePerNight: 85, amenities: ["WiFi", "Breakfast", "Metro"], style: "Clean, walkable, great value"),
            TourHotelOption(name: "Mercure / Hilton Garden Inn", city: "Paris / multi-city", neighbourhood: "City centre", stars: 4, rating: 8.7, pricePerNight: 165, amenities: ["Gym", "Restaurant", "Bar"], style: "Reliable 4★ comfort"),
            TourHotelOption(name: "Four Seasons George V / Ritz", city: "Paris", neighbourhood: "Champs-Élysées", stars: 5, rating: 9.6, pricePerNight: 780, amenities: ["Spa", "Michelin dining", "Butler"], style: "Palace-level luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Paris", title: "Paris classics", theme: "Icons & riverside",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Eiffel Tower", category: "Landmark", detail: "Summit or 2nd floor — book timed tickets.", ticketPriceUSD: 35, durationHours: 2.5, tip: "Skip-the-line tickets online."),
                            ItineraryActivity(time: "13:00", name: "Louvre Museum", category: "Museum", detail: "Mona Lisa + Denon wing highlights.", ticketPriceUSD: 22, durationHours: 3, tip: "Enter via Carrousel to skip crowds."),
                            ItineraryActivity(time: "17:30", name: "Seine sunset cruise", category: "Experience", detail: "1-hour bateaux mouches ride.", ticketPriceUSD: 18, durationHours: 1, tip: nil),
                        ],
                        mealsHint: "Café lunch near Louvre (~€18–25)", transportHint: "Navigo Easy / day pass ~€8.65"),
            DayTemplate(city: "Paris", title: "Montmartre & Left Bank", theme: "Art villages",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Sacré-Cœur & Place du Tertre", category: "Neighbourhood", detail: "Artists’ square & basilica views.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "13:00", name: "Musée d'Orsay", category: "Museum", detail: "Impressionist masterpieces.", ticketPriceUSD: 18, durationHours: 2.5, tip: "Combined ticket with Orangerie available."),
                            ItineraryActivity(time: "16:30", name: "Latin Quarter stroll", category: "Walk", detail: "Bookshops, Notre-Dame exterior, gelato.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Crêpes & wine in Montmartre (~€20)", transportHint: "Metro lines 2 & 12"),
            DayTemplate(city: "Amsterdam", title: "Amsterdam canals", theme: "Canal city day",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Canal cruise", category: "Experience", detail: "1-hour classic boat tour.", ticketPriceUSD: 20, durationHours: 1, tip: nil),
                            ItineraryActivity(time: "12:00", name: "Van Gogh Museum", category: "Museum", detail: "Timed-entry mandatory.", ticketPriceUSD: 24, durationHours: 2.5, tip: "Book 2–3 weeks ahead."),
                            ItineraryActivity(time: "16:00", name: "Jordaan neighbourhood", category: "Walk", detail: "Cafés, courtyards, flea markets.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Stroopwafel + Indonesian rijstafel (~€25)", transportHint: "GVB day ticket ~€9"),
            DayTemplate(city: "Rome", title: "Ancient Rome", theme: "Empire highlights",
                        activities: [
                            ItineraryActivity(time: "08:30", name: "Colosseum + Forum", category: "Landmark", detail: "Underground optional add-on.", ticketPriceUSD: 24, durationHours: 3.5, tip: "Roma Pass can bundle savings."),
                            ItineraryActivity(time: "14:00", name: "Pantheon & Piazza Navona", category: "Landmark", detail: "Free exterior; small Pantheon fee.", ticketPriceUSD: 5, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Trevi Fountain & Spanish Steps", category: "Walk", detail: "Evening lights are magical.", ticketPriceUSD: 0, durationHours: 2, tip: "Coin toss tradition — keep a euro."),
                        ],
                        mealsHint: "Trattoria near Campo de' Fiori (~€25–35)", transportHint: "Metro + walking; day ticket ~€7"),
            DayTemplate(city: "Barcelona", title: "Gaudí day", theme: "Modernisme",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Sagrada Família", category: "Landmark", detail: "Tower access extra.", ticketPriceUSD: 33, durationHours: 2.5, tip: "Book official site only."),
                            ItineraryActivity(time: "13:00", name: "Park Güell", category: "Park", detail: "Monumental zone ticketed.", ticketPriceUSD: 11, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Gothic Quarter & Rambla", category: "Walk", detail: "Tapas crawl evening.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                        ],
                        mealsHint: "Tapas + vermouth (~€20–30)", transportHint: "Hola Barcelona travel card"),
        ],
        tips: [
            "Get a Eurail / Interrail pass if visiting 3+ countries by train.",
            "Museum free days exist in many cities — check calendars.",
            "Carry a power adapter (Type C/F) and a light rain jacket.",
            "Validate metro tickets before boarding to avoid fines.",
        ]
    )

    static let france = DestinationProfile(
        displayName: "France",
        aliases: ["france", "paris", "french"],
        primaryAirport: AirportRef(code: "CDG", city: "Paris"),
        currency: "EUR (€)",
        bestSeason: "Apr–Jun & Sep–Oct",
        visaNote: "Schengen visa required for most Asian passports.",
        flightBaseUSD: 680,
        flightDuration: "12–15h",
        flightDurationShort: "10–12h",
        budgetArrival: "18:40+1",
        valueArrival: "13:55+1",
        premiumArrival: "12:20+1",
        luxuryArrival: "06:50+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: lufthansa,
        luxuryAirline: emirates,
        dailyFoodUSD: 48,
        dailyTransportUSD: 16,
        hotels: [
            TourHotelOption(name: "Hotel Ibis Paris Bastille", city: "Paris", neighbourhood: "Bastille", stars: 3, rating: 8.0, pricePerNight: 95, amenities: ["WiFi", "Metro", "Breakfast"], style: "Practical central 3★"),
            TourHotelOption(name: "Hôtel Le Six / Mercure Louvre", city: "Paris", neighbourhood: "St-Germain / Louvre", stars: 4, rating: 8.8, pricePerNight: 195, amenities: ["Bar", "Design rooms", "Concierge"], style: "Boutique 4★"),
            TourHotelOption(name: "Le Meurice / Plaza Athénée", city: "Paris", neighbourhood: "Tuileries / Alma", stars: 5, rating: 9.7, pricePerNight: 920, amenities: ["Palace spa", "Michelin", "Butler"], style: "Historic palace hotels"),
        ],
        itineraryTemplates: Array(europe.itineraryTemplates.filter { $0.city == "Paris" }) + [
            DayTemplate(city: "Versailles", title: "Palace of Versailles", theme: "Royal day trip",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Palace & Hall of Mirrors", category: "Palace", detail: "Passport ticket recommended.", ticketPriceUSD: 28, durationHours: 3, tip: "Arrive at opening."),
                            ItineraryActivity(time: "13:00", name: "Gardens & Marie Antoinette's Estate", category: "Gardens", detail: "Rent a bike in the park.", ticketPriceUSD: 12, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Picnic in the gardens (~€15)", transportHint: "RER C ~€5 each way"),
            DayTemplate(city: "Lyon", title: "Historic Lyon", theme: "Old town & gastronomy",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Vieux Lyon & Fourvière", category: "Heritage", detail: "Traboules, basilica and city views.", ticketPriceUSD: 0, durationHours: 3, tip: "Join an official traboule walking tour."),
                            ItineraryActivity(time: "14:00", name: "Musée des Confluences", category: "Museum", detail: "Science and anthropology beside the rivers.", ticketPriceUSD: 13, durationHours: 2.5, tip: nil),
                        ],
                        mealsHint: "Traditional bouchon dinner (~€30)", transportHint: "TGV Paris→Lyon ~2h"),
            DayTemplate(city: "Nice", title: "French Riviera", theme: "Coast & old town",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Promenade des Anglais", category: "Walk", detail: "Seafront walk into Vieux Nice.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "13:30", name: "Castle Hill & Matisse Museum", category: "Viewpoint", detail: "Panoramic bay views and modern art.", ticketPriceUSD: 10, durationHours: 3, tip: "Castle Hill lift is free."),
                        ],
                        mealsHint: "Socca and Niçoise food (~€20)", transportHint: "Tram + walking"),
            DayTemplate(city: "Strasbourg", title: "Alsace highlights", theme: "Canals & cathedral",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Strasbourg Cathedral", category: "Landmark", detail: "Astronomical clock and Gothic façade.", ticketPriceUSD: 4, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "13:00", name: "Petite France & canal cruise", category: "Experience", detail: "Half-timbered lanes and river locks.", ticketPriceUSD: 16, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Alsatian winstub (~€25)", transportHint: "TGV Paris→Strasbourg ~1h50"),
            DayTemplate(city: "Bordeaux", title: "Bordeaux & wine country", theme: "Architecture & vineyards",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Historic centre & Miroir d’Eau", category: "Walk", detail: "UNESCO quays and grand avenues.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "13:30", name: "Cité du Vin", category: "Museum", detail: "Interactive wine museum with tasting.", ticketPriceUSD: 24, durationHours: 3, tip: "Book Saint-Émilion separately for a full vineyard day."),
                        ],
                        mealsHint: "Market lunch and canelé (~€25)", transportHint: "TGV Paris→Bordeaux ~2h"),
        ],
        tips: europe.tips
    )

    static let italy = DestinationProfile(
        displayName: "Italy",
        aliases: ["italy", "rome", "venice", "florence", "milan", "italian"],
        primaryAirport: AirportRef(code: "FCO", city: "Rome"),
        currency: "EUR (€)",
        bestSeason: "Apr–Jun & Sep–Oct",
        visaNote: "Schengen visa. Book Colosseum & Vatican tickets weeks ahead.",
        flightBaseUSD: 710,
        flightDuration: "12–16h",
        flightDurationShort: "11–13h",
        budgetArrival: "20:15+1",
        valueArrival: "15:40+1",
        premiumArrival: "13:10+1",
        luxuryArrival: "08:00+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: lufthansa,
        luxuryAirline: emirates,
        dailyFoodUSD: 40,
        dailyTransportUSD: 15,
        hotels: [
            TourHotelOption(name: "Hotel Artemide / ibis Styles Roma", city: "Rome", neighbourhood: "Termini / Centro", stars: 3, rating: 8.3, pricePerNight: 110, amenities: ["WiFi", "Breakfast", "AC"], style: "Solid 3★ near transit"),
            TourHotelOption(name: "NH Collection / Hotel Eden wing", city: "Rome", neighbourhood: "Spanish Steps area", stars: 4, rating: 8.9, pricePerNight: 220, amenities: ["Rooftop", "Restaurant", "Spa"], style: "Upscale 4★"),
            TourHotelOption(name: "Hotel de Russie / Hassler", city: "Rome", neighbourhood: "Piazza del Popolo", stars: 5, rating: 9.5, pricePerNight: 650, amenities: ["Garden", "Spa", "Michelin"], style: "Roman luxury icons"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Rome", title: "Ancient Rome", theme: "Colosseum to Pantheon",
                        activities: [
                            ItineraryActivity(time: "08:30", name: "Colosseum + Roman Forum", category: "Landmark", detail: "Full archaeological park.", ticketPriceUSD: 24, durationHours: 3.5, tip: "Underground tour +€20."),
                            ItineraryActivity(time: "14:00", name: "Pantheon", category: "Landmark", detail: "Oculus & tombs.", ticketPriceUSD: 5, durationHours: 1, tip: nil),
                            ItineraryActivity(time: "16:00", name: "Gelato & Trevi", category: "Walk", detail: "Evening fountain lights.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Carbonara lunch (~€18)", transportHint: "Walk + Metro B"),
            DayTemplate(city: "Rome", title: "Vatican City", theme: "Art & faith",
                        activities: [
                            ItineraryActivity(time: "08:00", name: "Vatican Museums & Sistine Chapel", category: "Museum", detail: "Skip-the-line essential.", ticketPriceUSD: 30, durationHours: 3.5, tip: "Dress code: covered shoulders/knees."),
                            ItineraryActivity(time: "13:00", name: "St. Peter's Basilica", category: "Landmark", detail: "Dome climb optional.", ticketPriceUSD: 10, durationHours: 2, tip: "Dome €10 stairs / €8 lift+stairs."),
                            ItineraryActivity(time: "16:30", name: "Castel Sant'Angelo", category: "Viewpoint", detail: "River views at sunset.", ticketPriceUSD: 16, durationHours: 1.5, tip: nil),
                        ],
                        mealsHint: "Trastevere dinner (~€30)", transportHint: "Bus 40/64 or walk"),
            DayTemplate(city: "Florence", title: "Renaissance Florence", theme: "Art capital",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Uffizi Gallery", category: "Museum", detail: "Botticelli & Leonardo.", ticketPriceUSD: 28, durationHours: 3, tip: "Reserve timed entry."),
                            ItineraryActivity(time: "13:30", name: "Duomo complex", category: "Landmark", detail: "Cathedral free; dome climb ticketed.", ticketPriceUSD: 30, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Ponte Vecchio & sunset", category: "Walk", detail: "Golden hour over the Arno.", ticketPriceUSD: 0, durationHours: 1.5, tip: nil),
                        ],
                        mealsHint: "Florentine steak share (~€35 pp)", transportHint: "High-speed train Rome→Florence ~€20–45"),
        ],
        tips: [
            "Validate train tickets before boarding regional trains.",
            "Many churches enforce modest dress codes.",
            "Tap water is safe — refill bottles at public fountains.",
        ]
    )

    static let spain = DestinationProfile(
        displayName: "Spain",
        aliases: ["spain", "barcelona", "madrid", "spanish"],
        primaryAirport: AirportRef(code: "BCN", city: "Barcelona"),
        currency: "EUR (€)",
        bestSeason: "May–Jun & Sep–Oct",
        visaNote: "Schengen visa. Book Sagrada Família weeks ahead.",
        flightBaseUSD: 700,
        flightDuration: "13–17h",
        flightDurationShort: "11–14h",
        budgetArrival: "21:00+1",
        valueArrival: "16:20+1",
        premiumArrival: "14:00+1",
        luxuryArrival: "09:10+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: lufthansa,
        luxuryAirline: emirates,
        dailyFoodUSD: 38,
        dailyTransportUSD: 14,
        hotels: [
            TourHotelOption(name: "Generator / Catalonia hotels", city: "Barcelona", neighbourhood: "Gràcia / Eixample", stars: 3, rating: 8.2, pricePerNight: 90, amenities: ["WiFi", "Rooftop", "Metro"], style: "Vibrant 3★"),
            TourHotelOption(name: "Hotel Casa Fuster / NH Collection", city: "Barcelona", neighbourhood: "Passeig de Gràcia", stars: 4, rating: 8.9, pricePerNight: 185, amenities: ["Spa", "Restaurant", "Design"], style: "Stylish 4★"),
            TourHotelOption(name: "Hotel Arts / Mandarin Oriental", city: "Barcelona", neighbourhood: "Beach / Passeig", stars: 5, rating: 9.4, pricePerNight: 480, amenities: ["Beach", "Michelin", "Spa"], style: "Waterfront luxury"),
        ],
        itineraryTemplates: Array(europe.itineraryTemplates.filter { $0.city == "Barcelona" }) + [
            DayTemplate(city: "Madrid", title: "Madrid art triangle", theme: "Museums & plazas",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Prado Museum", category: "Museum", detail: "Velázquez & Goya.", ticketPriceUSD: 16, durationHours: 2.5, tip: "Free last 2 hours some evenings."),
                            ItineraryActivity(time: "14:00", name: "Retiro Park & Crystal Palace", category: "Park", detail: "Boat rental optional.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "18:00", name: "Tapas in La Latina", category: "Food", detail: "Bar hop Calle Cava Baja.", ticketPriceUSD: 25, durationHours: 2.5, tip: "Price is typical tapas spend."),
                        ],
                        mealsHint: "Included in tapas crawl", transportHint: "Metro day ticket ~€8"),
        ],
        tips: ["Late dinners are normal (21:00+).", "Siesta hours — some shops close 14:00–17:00."]
    )

    static let germany = DestinationProfile(
        displayName: "Germany",
        aliases: ["germany", "berlin", "munich", "frankfurt", "german"],
        primaryAirport: AirportRef(code: "FRA", city: "Frankfurt"),
        currency: "EUR (€)",
        bestSeason: "May–Sep",
        visaNote: "Schengen. Excellent ICE train network between cities.",
        flightBaseUSD: 670,
        flightDuration: "11–15h",
        flightDurationShort: "9–12h",
        budgetArrival: "17:50+1",
        valueArrival: "13:30+1",
        premiumArrival: "11:45+1",
        luxuryArrival: "06:20+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: lufthansa,
        luxuryAirline: emirates,
        dailyFoodUSD: 40,
        dailyTransportUSD: 16,
        hotels: [
            TourHotelOption(name: "Meininger / ibis Berlin", city: "Berlin", neighbourhood: "Mitte", stars: 3, rating: 8.0, pricePerNight: 80, amenities: ["WiFi", "Bar", "U-Bahn"], style: "Central budget"),
            TourHotelOption(name: "Hotel Adlon Kempinski wing / Titanic Chaussee", city: "Berlin", neighbourhood: "Brandenburg Gate", stars: 4, rating: 8.8, pricePerNight: 175, amenities: ["Spa", "Restaurant", "Gym"], style: "Comfort 4★"),
            TourHotelOption(name: "Hotel Adlon Kempinski", city: "Berlin", neighbourhood: "Unter den Linden", stars: 5, rating: 9.5, pricePerNight: 420, amenities: ["Spa", "Historic", "Fine dining"], style: "Landmark luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Berlin", title: "Berlin history", theme: "Wall & museums",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Brandenburg Gate & Reichstag dome", category: "Landmark", detail: "Reichstag free — register online.", ticketPriceUSD: 0, durationHours: 2, tip: "Book Reichstag weeks ahead."),
                            ItineraryActivity(time: "12:00", name: "Museum Island", category: "Museum", detail: "Pergamon / Neues Museum.", ticketPriceUSD: 22, durationHours: 3, tip: "Museum pass day ticket available."),
                            ItineraryActivity(time: "16:30", name: "East Side Gallery", category: "Walk", detail: "Open-air Wall murals.", ticketPriceUSD: 0, durationHours: 1.5, tip: nil),
                        ],
                        mealsHint: "Currywurst + craft beer (~€15)", transportHint: "BVG day ticket ~€10"),
            DayTemplate(city: "Munich", title: "Bavarian Munich", theme: "Old town & parks",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Marienplatz & Frauenkirche", category: "Landmark", detail: "Glockenspiel at 11:00.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "13:00", name: "Residenz or BMW Welt", category: "Museum", detail: "Pick culture or cars.", ticketPriceUSD: 14, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Englischer Garten", category: "Park", detail: "Surfers at Eisbach.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Beer garden dinner (~€25)", transportHint: "ICE Berlin→Munich ~3.5–4h"),
            DayTemplate(city: "Hamburg", title: "Hamburg harbour", theme: "Maritime Germany",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Speicherstadt & Miniatur Wunderland", category: "Attraction", detail: "Warehouse district and vast model railway.", ticketPriceUSD: 22, durationHours: 3, tip: "Reserve a timed slot."),
                            ItineraryActivity(time: "14:00", name: "Elbphilharmonie Plaza & harbour ferry", category: "Viewpoint", detail: "Skyline terrace and public ferry ride.", ticketPriceUSD: 5, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Fish sandwich by the harbour (~€15)", transportHint: "ICE Berlin→Hamburg ~2h"),
            DayTemplate(city: "Cologne", title: "Cologne & the Rhine", theme: "Cathedral city",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Cologne Cathedral", category: "Landmark", detail: "Climb the south tower for Rhine views.", ticketPriceUSD: 8, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "13:00", name: "Old Town & Chocolate Museum", category: "Museum", detail: "Riverside lanes and interactive exhibits.", ticketPriceUSD: 15, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Kölsch and local dishes (~€22)", transportHint: "ICE from Frankfurt or Berlin"),
            DayTemplate(city: "Heidelberg", title: "Romantic Heidelberg", theme: "Castle & old university",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Heidelberg Castle", category: "Castle", detail: "Funicular, ruins and terrace views.", ticketPriceUSD: 12, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "13:00", name: "Old Town & Philosophers’ Walk", category: "Walk", detail: "Historic university lanes and river panorama.", ticketPriceUSD: 0, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Student-quarter dinner (~€20)", transportHint: "Train from Frankfurt ~1h"),
            DayTemplate(city: "Dresden", title: "Dresden art & architecture", theme: "Baroque heritage",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Zwinger Palace", category: "Museum", detail: "Old Masters gallery and courtyards.", ticketPriceUSD: 16, durationHours: 3, tip: nil),
                            ItineraryActivity(time: "14:00", name: "Frauenkirche & Brühl’s Terrace", category: "Landmark", detail: "Rebuilt old town beside the Elbe.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                        ],
                        mealsHint: "Saxon cuisine (~€22)", transportHint: "Train Berlin→Dresden ~2h"),
            DayTemplate(city: "Freiburg", title: "Black Forest gateway", theme: "Nature & medieval streets",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Freiburg old town & Münster", category: "Heritage", detail: "Market square, cathedral and medieval water channels.", ticketPriceUSD: 5, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "13:00", name: "Black Forest scenic excursion", category: "Nature", detail: "Hiking, villages and lake viewpoints.", ticketPriceUSD: 20, durationHours: 4, tip: "Regional transport is often included with local guest cards."),
                        ],
                        mealsHint: "Black Forest cake and regional dinner (~€25)", transportHint: "ICE/Regional train via Frankfurt"),
        ],
        tips: ["Cash still useful in smaller bakeries.", "Quiet hours (Ruhezeit) are taken seriously."]
    )

    static let unitedKingdom = DestinationProfile(
        displayName: "United Kingdom",
        aliases: ["united kingdom", "uk", "england", "london", "britain", "scotland"],
        primaryAirport: AirportRef(code: "LHR", city: "London"),
        currency: "GBP (£)",
        bestSeason: "May–Sep",
        visaNote: "Not Schengen — UK ETA or visa required separately.",
        flightBaseUSD: 650,
        flightDuration: "11–15h",
        flightDurationShort: "9–12h",
        budgetArrival: "16:40+1",
        valueArrival: "12:55+1",
        premiumArrival: "11:20+1",
        luxuryArrival: "05:45+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: british,
        luxuryAirline: emirates,
        dailyFoodUSD: 50,
        dailyTransportUSD: 22,
        hotels: [
            TourHotelOption(name: "Premier Inn / Travelodge Central", city: "London", neighbourhood: "Zone 1–2", stars: 3, rating: 8.1, pricePerNight: 120, amenities: ["WiFi", "Breakfast", "Tube"], style: "Reliable budget chains"),
            TourHotelOption(name: "Hilton London Bankside / Park Plaza", city: "London", neighbourhood: "South Bank", stars: 4, rating: 8.7, pricePerNight: 240, amenities: ["Gym", "River views", "Bar"], style: "Modern 4★"),
            TourHotelOption(name: "The Savoy / Claridge's", city: "London", neighbourhood: "Strand / Mayfair", stars: 5, rating: 9.6, pricePerNight: 750, amenities: ["Afternoon tea", "Spa", "Concierge"], style: "Heritage luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "London", title: "Royal London", theme: "Palaces & parks",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Tower of London", category: "Landmark", detail: "Crown Jewels & Yeoman tour.", ticketPriceUSD: 40, durationHours: 3, tip: "Combo with Thames cruise."),
                            ItineraryActivity(time: "14:00", name: "British Museum", category: "Museum", detail: "Free entry; donation welcome.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "17:30", name: "West End walk & Covent Garden", category: "Walk", detail: "Street performers & shops.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Pub lunch (~£18–25)", transportHint: "Oyster / contactless daily cap ~£8.50"),
            DayTemplate(city: "London", title: "Westminster & museums", theme: "Politics & art",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Changing of the Guard / Buckingham", category: "Experience", detail: "Check schedule — not daily in winter.", ticketPriceUSD: 0, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "11:00", name: "Westminster Abbey or Churchill War Rooms", category: "Landmark", detail: "Pick one deep dive.", ticketPriceUSD: 32, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "15:00", name: "London Eye", category: "Viewpoint", detail: "30-min capsule ride.", ticketPriceUSD: 35, durationHours: 1, tip: "River combo tickets cheaper."),
                        ],
                        mealsHint: "South Bank street food (~£15)", transportHint: "Walk along South Bank"),
        ],
        tips: ["Stand on the right on escalators.", "Many museums are free — budget for special exhibitions."]
    )

    static let switzerland = DestinationProfile(
        displayName: "Switzerland",
        aliases: ["switzerland", "swiss", "zurich", "geneva", "interlaken", "zermatt"],
        primaryAirport: AirportRef(code: "ZRH", city: "Zurich"),
        currency: "CHF",
        bestSeason: "Jun–Sep (Alps) · Dec–Mar (ski)",
        visaNote: "Schengen. Swiss Travel Pass covers most trains & boats.",
        flightBaseUSD: 750,
        flightDuration: "12–16h",
        flightDurationShort: "10–13h",
        budgetArrival: "19:20+1",
        valueArrival: "14:50+1",
        premiumArrival: "13:15+1",
        luxuryArrival: "07:40+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: lufthansa,
        luxuryAirline: emirates,
        dailyFoodUSD: 60,
        dailyTransportUSD: 35,
        hotels: [
            TourHotelOption(name: "ibis Zurich / EasyHotel", city: "Zurich", neighbourhood: "Near station", stars: 3, rating: 7.9, pricePerNight: 140, amenities: ["WiFi", "Tram"], style: "Expensive-country budget"),
            TourHotelOption(name: "Hotel Schweizerhof / Mandarin wing", city: "Bern / Zurich", neighbourhood: "Centre", stars: 4, rating: 8.8, pricePerNight: 280, amenities: ["Spa", "Views", "Restaurant"], style: "Alpine comfort"),
            TourHotelOption(name: "Baur au Lac / Kulm Interlaken", city: "Zurich / Interlaken", neighbourhood: "Lake / Alps", stars: 5, rating: 9.6, pricePerNight: 680, amenities: ["Lake view", "Spa", "Fine dining"], style: "Classic Swiss luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Zurich", title: "Zurich lakeside", theme: "City & lake",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Old Town & Grossmünster", category: "Walk", detail: "Climb the tower for views.", ticketPriceUSD: 5, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "13:00", name: "Lake Zurich cruise", category: "Experience", detail: "Short round-trip boat.", ticketPriceUSD: 12, durationHours: 1.5, tip: "Covered by Travel Pass."),
                            ItineraryActivity(time: "16:00", name: "Bahnhofstrasse shopping", category: "Walk", detail: "Window shopping & chocolatiers.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Raclette or Zürich Geschnetzeltes (~CHF 35)", transportHint: "ZVV day pass"),
            DayTemplate(city: "Interlaken", title: "Jungfrau region", theme: "Alpine peaks",
                        activities: [
                            ItineraryActivity(time: "08:00", name: "Jungfraujoch – Top of Europe", category: "Mountain", detail: "Train via Grindelwald/Lauterbrunnen.", ticketPriceUSD: 210, durationHours: 6, tip: "Swiss Pass holders get big discounts."),
                            ItineraryActivity(time: "16:00", name: "Harder Kulm or lakeside stroll", category: "Viewpoint", detail: "Sunset over twin lakes.", ticketPriceUSD: 28, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Mountain restaurant lunch (~CHF 40)", transportHint: "Swiss Travel Pass recommended"),
        ],
        tips: ["Switzerland is pricey — picnic lunches save a lot.", "Trains run like clockwork — no need to over-buffer."]
    )

    static let unitedStates = DestinationProfile(
        displayName: "United States",
        aliases: ["united states", "usa", "u.s.", "america", "new york", "nyc", "los angeles", "las vegas"],
        primaryAirport: AirportRef(code: "JFK", city: "New York"),
        currency: "USD ($)",
        bestSeason: "Apr–Jun & Sep–Nov",
        visaNote: "ESTA (Visa Waiver) or B1/B2 visa depending on passport.",
        flightBaseUSD: 920,
        flightDuration: "16–22h",
        flightDurationShort: "14–18h",
        budgetArrival: "23:10+1",
        valueArrival: "18:30+1",
        premiumArrival: "16:00+1",
        luxuryArrival: "10:20+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: delta,
        luxuryAirline: emirates,
        dailyFoodUSD: 55,
        dailyTransportUSD: 25,
        hotels: [
            TourHotelOption(name: "Pod Hotels / Freehand", city: "New York", neighbourhood: "Midtown / Flatiron", stars: 3, rating: 8.0, pricePerNight: 145, amenities: ["WiFi", "Rooftop", "Compact rooms"], style: "Smart budget NYC"),
            TourHotelOption(name: "Hilton Midtown / Hyatt Grand Central", city: "New York", neighbourhood: "Midtown", stars: 4, rating: 8.6, pricePerNight: 280, amenities: ["Gym", "Restaurant", "Central"], style: "Full-service 4★"),
            TourHotelOption(name: "The Plaza / Four Seasons", city: "New York", neighbourhood: "5th Avenue", stars: 5, rating: 9.4, pricePerNight: 750, amenities: ["Spa", "Iconic", "Concierge"], style: "Landmark luxury"),
        ],
        itineraryTemplates: naMultiDays(["United States"]).filter { $0.city == "New York" } + [
            DayTemplate(city: "New York", title: "Neighbourhoods & viewpoints", theme: "Local New York",
                        activities: [
                            ItineraryActivity(time: "11:00", name: "High Line & Chelsea Market", category: "Walk", detail: "Elevated park + food hall.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "15:00", name: "One World Observatory", category: "Viewpoint", detail: "Downtown skyline.", ticketPriceUSD: 38, durationHours: 1.5, tip: nil),
                        ],
                        mealsHint: "Chelsea Market (~$20)", transportHint: "Subway"),
        ],
        tips: [
            "Sales tax (~8%) is added at checkout — not on price tags.",
            "Tip 15–20% at restaurants.",
            "Book Broadway & popular museums in advance.",
        ]
    )

    static let canada = DestinationProfile(
        displayName: "Canada",
        aliases: ["canada", "toronto", "vancouver", "montreal", "niagara"],
        primaryAirport: AirportRef(code: "YYZ", city: "Toronto"),
        currency: "CAD ($)",
        bestSeason: "Jun–Sep · Fall colours late Sep–Oct",
        visaNote: "eTA for visa-exempt travellers; visitor visa otherwise.",
        flightBaseUSD: 950,
        flightDuration: "17–23h",
        flightDurationShort: "15–19h",
        budgetArrival: "22:00+1",
        valueArrival: "17:10+1",
        premiumArrival: "15:00+1",
        luxuryArrival: "09:30+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: airCanada,
        luxuryAirline: emirates,
        dailyFoodUSD: 50,
        dailyTransportUSD: 20,
        hotels: [
            TourHotelOption(name: "Holiday Inn Express / Chelsea Hotel", city: "Toronto", neighbourhood: "Downtown", stars: 3, rating: 8.1, pricePerNight: 110, amenities: ["WiFi", "Breakfast", "Pool"], style: "Family-friendly 3★"),
            TourHotelOption(name: "Marriott City Centre / Fairmont wing", city: "Toronto", neighbourhood: "Financial District", stars: 4, rating: 8.8, pricePerNight: 220, amenities: ["Gym", "Restaurant", "Views"], style: "Business comfort"),
            TourHotelOption(name: "Four Seasons Toronto / Fairmont Royal York", city: "Toronto", neighbourhood: "Yorkville / Union", stars: 5, rating: 9.4, pricePerNight: 480, amenities: ["Spa", "Fine dining", "Concierge"], style: "Canadian luxury"),
        ],
        itineraryTemplates: Array(naMultiDays(["Canada"]).prefix(2)) + [
            DayTemplate(city: "Toronto", title: "Culture & islands", theme: "Museums & ferry",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "ROM or AGO", category: "Museum", detail: "World-class collections.", ticketPriceUSD: 23, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "14:00", name: "Toronto Islands ferry", category: "Nature", detail: "Bike rental on the islands.", ticketPriceUSD: 10, durationHours: 3, tip: "Ferry ~CAD 10 return."),
                        ],
                        mealsHint: "Queen St West dinner (~$30)", transportHint: "TTC + ferry"),
        ],
        tips: ["Weather turns fast — pack layers.", "Niagara is an easy day trip from Toronto."]
    )

    static let japan = DestinationProfile(
        displayName: "Japan",
        aliases: ["japan", "tokyo", "osaka", "kyoto", "japanese"],
        primaryAirport: AirportRef(code: "NRT", city: "Tokyo"),
        currency: "JPY (¥)",
        bestSeason: "Mar–May (sakura) · Oct–Nov (koyo)",
        visaNote: "Many nationalities visa-free short stay; check latest MOFA rules.",
        flightBaseUSD: 780,
        flightDuration: "12–16h",
        flightDurationShort: "10–13h",
        budgetArrival: "18:00+1",
        valueArrival: "14:30+1",
        premiumArrival: "12:45+1",
        luxuryArrival: "07:15+1",
        valueStops: "1 stop",
        budgetAirline: thai,
        valueAirline: qatar,
        premiumAirline: ana,
        luxuryAirline: singaporeAirlines,
        dailyFoodUSD: 40,
        dailyTransportUSD: 25,
        hotels: [
            TourHotelOption(name: "Toyoko Inn / APA Hotel", city: "Tokyo", neighbourhood: "Shinjuku / Asakusa", stars: 3, rating: 8.0, pricePerNight: 85, amenities: ["WiFi", "Compact", "Station"], style: "Efficient Japanese business hotels"),
            TourHotelOption(name: "Hotel Gracery / Mitsui Garden", city: "Tokyo", neighbourhood: "Shinjuku / Ginza", stars: 4, rating: 8.7, pricePerNight: 180, amenities: ["Onsen bath", "Restaurant", "Views"], style: "Polished 4★"),
            TourHotelOption(name: "Aman Tokyo / Park Hyatt", city: "Tokyo", neighbourhood: "Otemachi / Shinjuku", stars: 5, rating: 9.6, pricePerNight: 650, amenities: ["Spa", "Sky bar", "Butler"], style: "Ultra luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Tokyo", title: "Classic Tokyo", theme: "Temples & neon",
                        activities: [
                            ItineraryActivity(time: "08:30", name: "Senso-ji Asakusa", category: "Temple", detail: "Nakamise shopping street.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "12:00", name: "teamLab Planets or Borderless", category: "Experience", detail: "Immersive digital art.", ticketPriceUSD: 38, durationHours: 2.5, tip: "Book weeks ahead."),
                            ItineraryActivity(time: "16:30", name: "Shibuya Crossing & sky deck", category: "Viewpoint", detail: "Scramble crossing + optional Mag House.", ticketPriceUSD: 12, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Ramen + convenience snacks (~¥2,000)", transportHint: "Suica/Pasmo IC card"),
            DayTemplate(city: "Tokyo", title: "Modern & traditional", theme: "Harajuku to Imperial",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Meiji Jingu", category: "Shrine", detail: "Forest walk from Harajuku.", ticketPriceUSD: 0, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "11:00", name: "Harajuku & Takeshita Street", category: "Walk", detail: "Youth fashion & crepes.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "15:00", name: "Tokyo Skytree", category: "Viewpoint", detail: "Tembo Deck ticket.", ticketPriceUSD: 23, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Sushi conveyor or izakaya (~¥3,000)", transportHint: "JR Yamanote loop"),
            DayTemplate(city: "Kyoto", title: "Kyoto temples", theme: "Ancient capital",
                        activities: [
                            ItineraryActivity(time: "08:00", name: "Fushimi Inari", category: "Shrine", detail: "Thousand torii gates — go early.", ticketPriceUSD: 0, durationHours: 2.5, tip: "Beat tour buses at 7–8 am."),
                            ItineraryActivity(time: "12:00", name: "Kiyomizu-dera", category: "Temple", detail: "Wooden stage & Higashiyama lanes.", ticketPriceUSD: 4, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "16:00", name: "Arashiyama bamboo (if time)", category: "Nature", detail: "Or Gion at dusk.", ticketPriceUSD: 0, durationHours: 2, tip: "Shinkansen Tokyo→Kyoto ~2.5h / ~$110."),
                        ],
                        mealsHint: "Tofu kaiseki or matcha sweets (~¥2,500)", transportHint: "JR Pass if multi-city"),
        ],
        tips: ["Cash still common at small temples & stalls.", "Never tip — it's not part of the culture.", "Buy a Pocket Wi‑Fi or eSIM."]
    )

    static let thailand = DestinationProfile(
        displayName: "Thailand",
        aliases: ["thailand", "bangkok", "phuket", "chiang mai", "thai"],
        primaryAirport: AirportRef(code: "BKK", city: "Bangkok"),
        currency: "THB (฿)",
        bestSeason: "Nov–Feb (cool & dry)",
        visaNote: "Many nationalities get visa exemption 30–60 days — verify before travel.",
        flightBaseUSD: 420,
        flightDuration: "6–9h",
        flightDurationShort: "5–7h",
        budgetArrival: "14:20",
        valueArrival: "12:10",
        premiumArrival: "11:00",
        luxuryArrival: "08:40",
        valueStops: "Non-stop / 1 stop",
        budgetAirline: flydubai,
        valueAirline: thai,
        premiumAirline: singaporeAirlines,
        luxuryAirline: emirates,
        dailyFoodUSD: 25,
        dailyTransportUSD: 12,
        hotels: [
            TourHotelOption(name: "Lub d / ibis Styles Sukhumvit", city: "Bangkok", neighbourhood: "Sukhumvit", stars: 3, rating: 8.3, pricePerNight: 45, amenities: ["Pool", "BTS", "WiFi"], style: "Fun budget"),
            TourHotelOption(name: "Hotel Indigo / Avani+", city: "Bangkok", neighbourhood: "Riverside / Sukhumvit", stars: 4, rating: 8.8, pricePerNight: 95, amenities: ["Rooftop pool", "Spa", "River"], style: "Design 4★"),
            TourHotelOption(name: "Mandarin Oriental / Capella", city: "Bangkok", neighbourhood: "Chao Phraya", stars: 5, rating: 9.6, pricePerNight: 380, amenities: ["Legendary service", "Spa", "Dining"], style: "World-famous luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Bangkok", title: "Temples & river", theme: "Sacred Bangkok",
                        activities: [
                            ItineraryActivity(time: "08:00", name: "Grand Palace & Wat Phra Kaew", category: "Palace", detail: "Dress code enforced.", ticketPriceUSD: 15, durationHours: 2.5, tip: "Rent cover-ups on site if needed."),
                            ItineraryActivity(time: "12:00", name: "Wat Arun", category: "Temple", detail: "Cross by river ferry.", ticketPriceUSD: 3, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "16:00", name: "Chao Phraya dinner cruise", category: "Experience", detail: "Sunset skyline.", ticketPriceUSD: 35, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Street food lunch (~$5–8)", transportHint: "BTS + river boat"),
            DayTemplate(city: "Bangkok", title: "Markets & malls", theme: "Shopping day",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Chatuchak Weekend Market", category: "Market", detail: "Open Sat–Sun mainly.", ticketPriceUSD: 0, durationHours: 3, tip: "Go early before heat."),
                            ItineraryActivity(time: "14:00", name: "Jim Thompson House", category: "Museum", detail: "Silk heritage teak house.", ticketPriceUSD: 6, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Asiatique or ICONSIAM", category: "Waterfront", detail: "Shopping & night views.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                        ],
                        mealsHint: "Night market (~$8–12)", transportHint: "BTS day pass"),
        ],
        tips: ["Drink bottled water.", "Negotiate tuk-tuk fares or use Grab.", "Temple etiquette: shoulders & knees covered."]
    )

    static let turkey = DestinationProfile(
        displayName: "Turkey",
        aliases: ["turkey", "türkiye", "istanbul", "cappadocia", "turkish"],
        primaryAirport: AirportRef(code: "IST", city: "Istanbul"),
        currency: "TRY (₺)",
        bestSeason: "Apr–Jun & Sep–Oct",
        visaNote: "eVisa available online for many nationalities in minutes.",
        flightBaseUSD: 480,
        flightDuration: "6–9h",
        flightDurationShort: "5–7h",
        budgetArrival: "13:40",
        valueArrival: "11:20",
        premiumArrival: "10:05",
        luxuryArrival: "07:50",
        valueStops: "Non-stop",
        budgetAirline: pia,
        valueAirline: turkish,
        premiumAirline: qatar,
        luxuryAirline: turkish,
        dailyFoodUSD: 30,
        dailyTransportUSD: 12,
        hotels: [
            TourHotelOption(name: "Sirkeci inns / The Vault Karaköy wing", city: "Istanbul", neighbourhood: "Sultanahmet / Karaköy", stars: 3, rating: 8.2, pricePerNight: 70, amenities: ["Breakfast", "Terrace", "Tram"], style: "Historic-quarter 3★"),
            TourHotelOption(name: "CVK Park Bosphorus / Swissôtel", city: "Istanbul", neighbourhood: "Beşiktaş / Maçka", stars: 4, rating: 8.8, pricePerNight: 150, amenities: ["Pool", "Bosphorus view", "Spa"], style: "Modern 4★"),
            TourHotelOption(name: "Four Seasons Sultanahmet / Ciragan Palace", city: "Istanbul", neighbourhood: "Old City / Bosphorus", stars: 5, rating: 9.5, pricePerNight: 420, amenities: ["Palace", "Spa", "Dining"], style: "Ottoman luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Istanbul", title: "Old City icons", theme: "Byzantine & Ottoman",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Hagia Sophia", category: "Landmark", detail: "Mosque visit — free entry.", ticketPriceUSD: 0, durationHours: 1.5, tip: "Dress modestly."),
                            ItineraryActivity(time: "11:00", name: "Blue Mosque & Hippodrome", category: "Landmark", detail: "Exterior + courtyard.", ticketPriceUSD: 0, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "14:00", name: "Topkapi Palace", category: "Palace", detail: "Harem section extra.", ticketPriceUSD: 25, durationHours: 3, tip: "Museum Pass Istanbul saves money."),
                        ],
                        mealsHint: "Kebab lunch near Grand Bazaar (~$12)", transportHint: "Tram T1"),
            DayTemplate(city: "Istanbul", title: "Bosphorus & bazaars", theme: "Water & markets",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Bosphorus cruise", category: "Experience", detail: "Short public ferry or tour.", ticketPriceUSD: 15, durationHours: 2, tip: "Public ferry is cheapest."),
                            ItineraryActivity(time: "13:00", name: "Grand Bazaar & Spice Bazaar", category: "Market", detail: "Haggle politely.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Galata Tower", category: "Viewpoint", detail: "Golden Horn views.", ticketPriceUSD: 20, durationHours: 1.5, tip: "Book timed slot."),
                        ],
                        mealsHint: "Meze dinner in Beyoğlu (~$20)", transportHint: "Ferry + funicular"),
        ],
        tips: ["Get an Istanbulkart for all transit.", "Cappadocia balloons are worth a weekend add-on."]
    )

    static let uae = DestinationProfile(
        displayName: "UAE / Dubai",
        aliases: ["uae", "dubai", "abu dhabi", "emirates"],
        primaryAirport: AirportRef(code: "DXB", city: "Dubai"),
        currency: "AED",
        bestSeason: "Oct–Apr (cooler)",
        visaNote: "Many nationalities get visa on arrival / pre-arranged UAE visa.",
        flightBaseUSD: 280,
        flightDuration: "2h 45m–4h",
        flightDurationShort: "2h 45m",
        budgetArrival: "08:15",
        valueArrival: "11:50",
        premiumArrival: "11:50",
        luxuryArrival: "08:15",
        valueStops: "Non-stop",
        budgetAirline: flydubai,
        valueAirline: emirates,
        premiumAirline: emirates,
        luxuryAirline: emirates,
        dailyFoodUSD: 45,
        dailyTransportUSD: 15,
        hotels: [
            TourHotelOption(name: "ibis Al Barsha", city: "Dubai", neighbourhood: "Al Barsha", stars: 3, rating: 8.4, pricePerNight: 67, amenities: ["Metro", "WiFi", "Pool"], style: "Best-value 3★"),
            TourHotelOption(name: "JW Marriott Marquis", city: "Dubai", neighbourhood: "Business Bay", stars: 4, rating: 9.1, pricePerNight: 145, amenities: ["Spa", "Pool", "Views"], style: "Tallest 4★ comfort"),
            TourHotelOption(name: "Burj Al Arab / Atlantis The Palm", city: "Dubai", neighbourhood: "Jumeirah / Palm", stars: 5, rating: 9.7, pricePerNight: 320, amenities: ["Butler", "Beach", "Waterpark"], style: "Iconic 5★"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Dubai", title: "Modern Dubai", theme: "Skyline icons",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Burj Khalifa At the Top", category: "Landmark", detail: "Floors 124/125.", ticketPriceUSD: 45, durationHours: 1.5, tip: "Sunset slots cost more."),
                            ItineraryActivity(time: "13:00", name: "Dubai Mall & Fountain", category: "Shopping", detail: "Aquarium optional.", ticketPriceUSD: 0, durationHours: 3, tip: "Fountain shows every 30 min evenings."),
                            ItineraryActivity(time: "17:30", name: "Dubai Frame", category: "Viewpoint", detail: "Old vs new city views.", ticketPriceUSD: 14, durationHours: 1.5, tip: nil),
                        ],
                        mealsHint: "Mall food court or fine dining (~$20–60)", transportHint: "Metro Red Line + taxi"),
            DayTemplate(city: "Dubai", title: "Culture & desert", theme: "Heritage + dune",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Al Fahidi & Dubai Museum", category: "Heritage", detail: "Abra across the Creek.", ticketPriceUSD: 1, durationHours: 2.5, tip: "Abra ~AED 1."),
                            ItineraryActivity(time: "15:00", name: "Desert safari", category: "Adventure", detail: "Dune bashing, BBQ, shows.", ticketPriceUSD: 55, durationHours: 6, tip: "Book shared vs private."),
                        ],
                        mealsHint: "BBQ often included in safari", transportHint: "Hotel pickup usual"),
        ],
        tips: ["Dress modestly in old Dubai & mosques.", "Friday brunch culture is huge — book ahead."]
    )

    static let maldives = DestinationProfile(
        displayName: "Maldives",
        aliases: ["maldives", "male", "maldivian"],
        primaryAirport: AirportRef(code: "MLE", city: "Malé"),
        currency: "USD / MVR",
        bestSeason: "Nov–Apr (dry)",
        visaNote: "Free 30-day visa on arrival for most passports with hotel booking + funds proof.",
        flightBaseUSD: 650,
        flightDuration: "6–10h",
        flightDurationShort: "5–8h",
        budgetArrival: "16:00",
        valueArrival: "13:20",
        premiumArrival: "12:00",
        luxuryArrival: "09:40",
        valueStops: "1 stop",
        budgetAirline: flydubai,
        valueAirline: emirates,
        premiumAirline: singaporeAirlines,
        luxuryAirline: qatar,
        dailyFoodUSD: 80,
        dailyTransportUSD: 40,
        hotels: [
            TourHotelOption(name: "Local island guesthouse (Maafushi)", city: "Maafushi", neighbourhood: "Local island", stars: 3, rating: 8.0, pricePerNight: 90, amenities: ["Fan/AC", "Breakfast", "Snorkel"], style: "Budget local-island stay"),
            TourHotelOption(name: "Adaaran / Centara resorts", city: "North Malé Atoll", neighbourhood: "Resort island", stars: 4, rating: 8.7, pricePerNight: 280, amenities: ["All-inclusive options", "House reef", "Pool"], style: "Mid-range resort"),
            TourHotelOption(name: "Soneva / Four Seasons", city: "Various atolls", neighbourhood: "Private island", stars: 5, rating: 9.7, pricePerNight: 1200, amenities: ["Water villa", "Spa", "Seaplane"], style: "Bucket-list luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Malé / Resort", title: "Arrival & reef", theme: "Settle into island life",
                        activities: [
                            ItineraryActivity(time: "11:00", name: "Speedboat / seaplane transfer", category: "Transfer", detail: "Included or extra by resort.", ticketPriceUSD: 120, durationHours: 1.5, tip: "Seaplane only in daylight."),
                            ItineraryActivity(time: "15:00", name: "House reef snorkel", category: "Water", detail: "Gear often free for guests.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Resort half-board recommended", transportHint: "Island is walkable"),
            DayTemplate(city: "Resort", title: "Ocean day", theme: "Sandbank & dive",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Sandbank picnic", category: "Experience", detail: "Private or shared excursion.", ticketPriceUSD: 95, durationHours: 4, tip: nil),
                            ItineraryActivity(time: "15:00", name: "Intro dive or sunset cruise", category: "Water", detail: "Discover scuba or dolphin cruise.", ticketPriceUSD: 110, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Overwater restaurant dinner", transportHint: "Resort boats"),
        ],
        tips: ["Almost everything is USD-priced at resorts.", "Alcohol only on resort islands, not local islands."]
    )

    static let australia = DestinationProfile(
        displayName: "Australia",
        aliases: ["australia", "sydney", "melbourne", "aussie"],
        primaryAirport: AirportRef(code: "SYD", city: "Sydney"),
        currency: "AUD ($)",
        bestSeason: "Sep–Nov & Mar–May",
        visaNote: "ETA/eVisitor required before departure for most travellers.",
        flightBaseUSD: 1100,
        flightDuration: "14–20h",
        flightDurationShort: "12–16h",
        budgetArrival: "22:40+1",
        valueArrival: "18:10+1",
        premiumArrival: "16:30+1",
        luxuryArrival: "11:00+1",
        valueStops: "1 stop",
        budgetAirline: thai,
        valueAirline: singaporeAirlines,
        premiumAirline: qatar,
        luxuryAirline: emirates,
        dailyFoodUSD: 55,
        dailyTransportUSD: 22,
        hotels: [
            TourHotelOption(name: "ibis Styles / Mantra", city: "Sydney", neighbourhood: "Darling Harbour", stars: 3, rating: 8.1, pricePerNight: 130, amenities: ["WiFi", "Pool", "Ferry"], style: "Central value"),
            TourHotelOption(name: "Hyatt Regency / Marriott Circular Quay", city: "Sydney", neighbourhood: "Harbour", stars: 4, rating: 8.8, pricePerNight: 260, amenities: ["Harbour view", "Gym", "Dining"], style: "Harbour 4★"),
            TourHotelOption(name: "Park Hyatt Sydney / Shangri-La", city: "Sydney", neighbourhood: "The Rocks", stars: 5, rating: 9.5, pricePerNight: 650, amenities: ["Opera House views", "Spa", "Concierge"], style: "Iconic harbour luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Sydney", title: "Harbour icons", theme: "Opera & bridge",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Sydney Opera House tour", category: "Landmark", detail: "Guided interior tour.", ticketPriceUSD: 30, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "12:00", name: "Harbour Bridge Climb or Pylon Lookout", category: "Viewpoint", detail: "Climb is pricey; lookout cheaper.", ticketPriceUSD: 20, durationHours: 2, tip: "Full BridgeClimb ~$200+."),
                            ItineraryActivity(time: "16:00", name: "Ferry to Manly", category: "Ferry", detail: "Scenic harbour crossing.", ticketPriceUSD: 10, durationHours: 3, tip: "Opal card taps."),
                        ],
                        mealsHint: "Fish & chips at Manly (~$20)", transportHint: "Opal card"),
        ],
        tips: ["Strong sun — SPF is essential.", "Wildlife encounters: book Taronga Zoo if time."]
    )

    static let singapore = DestinationProfile(
        displayName: "Singapore",
        aliases: ["singapore", "sg", "marina bay"],
        primaryAirport: AirportRef(code: "SIN", city: "Singapore"),
        currency: "SGD ($)",
        bestSeason: "Feb–Apr (drier spells)",
        visaNote: "Visa-free short stays for many nationalities.",
        flightBaseUSD: 480,
        flightDuration: "6–9h",
        flightDurationShort: "5–7h",
        budgetArrival: "15:00",
        valueArrival: "12:40",
        premiumArrival: "11:20",
        luxuryArrival: "08:50",
        valueStops: "Non-stop / 1 stop",
        budgetAirline: thai,
        valueAirline: singaporeAirlines,
        premiumAirline: singaporeAirlines,
        luxuryAirline: singaporeAirlines,
        dailyFoodUSD: 35,
        dailyTransportUSD: 12,
        hotels: [
            TourHotelOption(name: "Hotel Boss / ibis Novena", city: "Singapore", neighbourhood: "Bugis / Novena", stars: 3, rating: 8.2, pricePerNight: 95, amenities: ["MRT", "WiFi", "Breakfast"], style: "Clean efficient 3★"),
            TourHotelOption(name: "Marina Bay Sands wing / Pan Pacific", city: "Singapore", neighbourhood: "Marina / City Hall", stars: 4, rating: 8.9, pricePerNight: 240, amenities: ["Pool", "Mall access", "Views"], style: "Prime location 4★"),
            TourHotelOption(name: "Marina Bay Sands / Raffles", city: "Singapore", neighbourhood: "Marina Bay", stars: 5, rating: 9.5, pricePerNight: 520, amenities: ["Infinity pool", "Casino", "Heritage"], style: "Bucket-list luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Singapore", title: "Marina Bay", theme: "Futuristic waterfront",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Gardens by the Bay", category: "Attraction", detail: "Conservatories + Supertree Grove.", ticketPriceUSD: 24, durationHours: 3, tip: "Free outdoor gardens; domes ticketed."),
                            ItineraryActivity(time: "15:00", name: "Marina Bay Sands SkyPark", category: "Viewpoint", detail: "Observation deck if not a hotel guest.", ticketPriceUSD: 26, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "19:30", name: "Spectra light show", category: "Show", detail: "Free evening fountain show.", ticketPriceUSD: 0, durationHours: 1, tip: nil),
                        ],
                        mealsHint: "Hawker centre (~$6–10)", transportHint: "MRT"),
            DayTemplate(city: "Singapore", title: "Culture triangle", theme: "Heritage quarters",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Chinatown & Buddha Tooth Relic", category: "Neighbourhood", detail: "Temples & street food.", ticketPriceUSD: 0, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "13:00", name: "National Gallery or ArtScience", category: "Museum", detail: "Pick art or science.", ticketPriceUSD: 20, durationHours: 2.5, tip: nil),
                            ItineraryActivity(time: "17:00", name: "Sentosa (cable car optional)", category: "Island", detail: "Beaches & Universal add-on.", ticketPriceUSD: 15, durationHours: 3, tip: "Universal tickets separate ~$60+."),
                        ],
                        mealsHint: "Maxwell Food Centre (~$8)", transportHint: "MRT + Sentosa express"),
        ],
        tips: ["Chewing gum import is restricted.", "Hawker centres are safe, cheap, and excellent."]
    )

    static let morocco = DestinationProfile(
        displayName: "Morocco",
        aliases: ["morocco", "marrakech", "casablanca", "fez", "moroccan"],
        primaryAirport: AirportRef(code: "RAK", city: "Marrakech"),
        currency: "MAD (DH)",
        bestSeason: "Mar–May & Sep–Nov",
        visaNote: "Visa-free for many nationalities up to 90 days.",
        flightBaseUSD: 620,
        flightDuration: "12–18h",
        flightDurationShort: "10–14h",
        budgetArrival: "20:00+1",
        valueArrival: "16:30+1",
        premiumArrival: "14:50+1",
        luxuryArrival: "10:10+1",
        valueStops: "1–2 stops",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: emirates,
        luxuryAirline: qatar,
        dailyFoodUSD: 28,
        dailyTransportUSD: 15,
        hotels: [
            TourHotelOption(name: "Riad 3★ medina guesthouse", city: "Marrakech", neighbourhood: "Medina", stars: 3, rating: 8.4, pricePerNight: 55, amenities: ["Rooftop", "Breakfast", "Patio"], style: "Authentic riad stay"),
            TourHotelOption(name: "Riad Kniza / Hotel & Spa", city: "Marrakech", neighbourhood: "Medina", stars: 4, rating: 9.0, pricePerNight: 140, amenities: ["Pool", "Spa", "Dinner"], style: "Boutique riad 4★"),
            TourHotelOption(name: "La Mamounia / Royal Mansour", city: "Marrakech", neighbourhood: "City / Medina", stars: 5, rating: 9.7, pricePerNight: 550, amenities: ["Palace gardens", "Spa", "Fine dining"], style: "Legendary luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Marrakech", title: "Medina immersion", theme: "Souks & squares",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Jemaa el-Fnaa & souks", category: "Market", detail: "Guided walk recommended first time.", ticketPriceUSD: 20, durationHours: 3, tip: "Guide helps with navigation & prices."),
                            ItineraryActivity(time: "13:00", name: "Bahia Palace", category: "Palace", detail: "19th-century riad complex.", ticketPriceUSD: 7, durationHours: 1.5, tip: nil),
                            ItineraryActivity(time: "16:00", name: "Jardin Majorelle", category: "Garden", detail: "Yves Saint Laurent gardens.", ticketPriceUSD: 15, durationHours: 2, tip: "Book timed entry."),
                        ],
                        mealsHint: "Tagine lunch (~$12)", transportHint: "Walk + petit taxi"),
        ],
        tips: ["Agree taxi fares before riding.", "Modest dress in medinas is appreciated."]
    )

    static let greece = DestinationProfile(
        displayName: "Greece",
        aliases: ["greece", "athens", "santorini", "mykonos", "greek"],
        primaryAirport: AirportRef(code: "ATH", city: "Athens"),
        currency: "EUR (€)",
        bestSeason: "May–Jun & Sep–Oct",
        visaNote: "Schengen visa. Island ferries book up in peak summer.",
        flightBaseUSD: 720,
        flightDuration: "12–17h",
        flightDurationShort: "10–14h",
        budgetArrival: "19:40+1",
        valueArrival: "15:20+1",
        premiumArrival: "13:40+1",
        luxuryArrival: "08:30+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: lufthansa,
        luxuryAirline: emirates,
        dailyFoodUSD: 40,
        dailyTransportUSD: 18,
        hotels: [
            TourHotelOption(name: "Athens Hub / Phaedra Hotel", city: "Athens", neighbourhood: "Plaka / Monastiraki", stars: 3, rating: 8.3, pricePerNight: 85, amenities: ["Acropolis views", "WiFi", "Roof"], style: "Central value"),
            TourHotelOption(name: "Electra Metropolis / NJV Athens Plaza", city: "Athens", neighbourhood: "Syntagma", stars: 4, rating: 8.8, pricePerNight: 175, amenities: ["Rooftop pool", "Restaurant"], style: "Polished 4★"),
            TourHotelOption(name: "Hotel Grande Bretagne / Canaves Oia", city: "Athens / Santorini", neighbourhood: "Syntagma / Oia", stars: 5, rating: 9.5, pricePerNight: 480, amenities: ["Historic", "Cave suites", "Infinity pool"], style: "Landmark & island luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Athens", title: "Acropolis day", theme: "Ancient Athens",
                        activities: [
                            ItineraryActivity(time: "08:00", name: "Acropolis & Parthenon", category: "Landmark", detail: "Combo ticket covers major sites.", ticketPriceUSD: 30, durationHours: 3, tip: "Go at opening — less heat & crowds."),
                            ItineraryActivity(time: "12:30", name: "Acropolis Museum", category: "Museum", detail: "Parthenon sculptures.", ticketPriceUSD: 15, durationHours: 2, tip: nil),
                            ItineraryActivity(time: "16:00", name: "Plaka & Anafiotika", category: "Walk", detail: "Whitewashed lanes under Acropolis.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Souvlaki & Greek salad (~€15)", transportHint: "Metro to Acropolis station"),
            DayTemplate(city: "Athens", title: "Agora & seaside", theme: "History + coast",
                        activities: [
                            ItineraryActivity(time: "09:30", name: "Ancient Agora", category: "Ruins", detail: "Temple of Hephaestus.", ticketPriceUSD: 10, durationHours: 2, tip: "Often in combo ticket."),
                            ItineraryActivity(time: "14:00", name: "Cape Sounion sunset", category: "Day trip", detail: "Temple of Poseidon.", ticketPriceUSD: 25, durationHours: 5, tip: "Tour price typical incl. transport."),
                        ],
                        mealsHint: "Seafood near marina (~€30)", transportHint: "Organised tour or rental car"),
        ],
        tips: ["Island hopping: book ferries early in July–August.", "Midday heat is intense — schedule ruins for morning."]
    )

    static let southAfrica = DestinationProfile(
        displayName: "South Africa",
        aliases: ["south africa", "south african", "cape town", "johannesburg", "kruger", "durban"],
        primaryAirport: AirportRef(code: "JNB", city: "Johannesburg"),
        currency: "ZAR (R)",
        bestSeason: "May–Sep (safari) · Oct–Mar (Cape Town beaches)",
        visaNote: "Many nationalities get visa-free entry — confirm for your passport before travel.",
        flightBaseUSD: 850,
        flightDuration: "14–20h",
        flightDurationShort: "12–16h",
        budgetArrival: "21:40+1",
        valueArrival: "17:20+1",
        premiumArrival: "15:10+1",
        luxuryArrival: "09:50+1",
        valueStops: "1 stop",
        budgetAirline: turkish,
        valueAirline: qatar,
        premiumAirline: emirates,
        luxuryAirline: qatar,
        dailyFoodUSD: 40,
        dailyTransportUSD: 25,
        hotels: [
            TourHotelOption(name: "City Lodge / Protea Hotel", city: "Johannesburg", neighbourhood: "Sandton / Rosebank", stars: 3, rating: 8.1, pricePerNight: 95, amenities: ["WiFi", "Breakfast", "Pool"], style: "Solid city value"),
            TourHotelOption(name: "Southern Sun / Radisson Blu", city: "Cape Town", neighbourhood: "V&A Waterfront", stars: 4, rating: 8.7, pricePerNight: 180, amenities: ["Harbour view", "Gym", "Restaurant"], style: "Waterfront comfort"),
            TourHotelOption(name: "One&Only Cape Town / Ellerman House", city: "Cape Town", neighbourhood: "Waterfront / Bantry Bay", stars: 5, rating: 9.6, pricePerNight: 520, amenities: ["Spa", "Ocean view", "Fine dining"], style: "Cape luxury"),
        ],
        itineraryTemplates: [
            DayTemplate(city: "Johannesburg", title: "Johannesburg arrival", theme: "City & heritage",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Apartheid Museum", category: "Museum", detail: "Essential modern history.", ticketPriceUSD: 12, durationHours: 3, tip: "Book timed entry."),
                            ItineraryActivity(time: "14:30", name: "Soweto highlights tour", category: "Heritage", detail: "Vilakazi Street and Mandela House.", ticketPriceUSD: 35, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Sandton dinner (~$25)", transportHint: "Uber / organised tour"),
            DayTemplate(city: "Kruger", title: "Safari day", theme: "Big Five wildlife",
                        activities: [
                            ItineraryActivity(time: "05:30", name: "Morning game drive", category: "Safari", detail: "Open vehicle wildlife viewing.", ticketPriceUSD: 90, durationHours: 4, tip: "Warm layers for dawn."),
                            ItineraryActivity(time: "15:30", name: "Afternoon / sunset drive", category: "Safari", detail: "Second drive for different sightings.", ticketPriceUSD: 80, durationHours: 3.5, tip: nil),
                        ],
                        mealsHint: "Lodge meals usually included", transportHint: "Flight or road transfer from Johannesburg"),
            DayTemplate(city: "Cape Town", title: "Table Mountain & Waterfront", theme: "Iconic Cape Town",
                        activities: [
                            ItineraryActivity(time: "09:00", name: "Table Mountain cableway", category: "Landmark", detail: "Summit views over the city bowl.", ticketPriceUSD: 25, durationHours: 3, tip: "Go early — wind can close the cableway."),
                            ItineraryActivity(time: "14:00", name: "V&A Waterfront", category: "Waterfront", detail: "Shops, harbour and sunset photos.", ticketPriceUSD: 0, durationHours: 3, tip: nil),
                        ],
                        mealsHint: "Waterfront seafood (~$30)", transportHint: "MyCiTi bus + Uber"),
            DayTemplate(city: "Cape Town", title: "Cape Peninsula", theme: "Coast & penguins",
                        activities: [
                            ItineraryActivity(time: "08:30", name: "Chapman’s Peak & Cape Point", category: "Nature", detail: "Scenic drive to the peninsula tip.", ticketPriceUSD: 20, durationHours: 4, tip: "Park entry fees apply."),
                            ItineraryActivity(time: "14:00", name: "Boulders Beach penguins", category: "Wildlife", detail: "African penguin colony.", ticketPriceUSD: 12, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Kalk Bay lunch (~$20)", transportHint: "Full-day peninsula tour recommended"),
            DayTemplate(city: "Stellenbosch", title: "Winelands day", theme: "Vineyards & Cape Dutch",
                        activities: [
                            ItineraryActivity(time: "10:00", name: "Stellenbosch wine tasting", category: "Wine", detail: "2–3 estate tastings.", ticketPriceUSD: 40, durationHours: 5, tip: "Use a driver / tour — don’t self-drive after tasting."),
                            ItineraryActivity(time: "16:00", name: "Franschhoek valley stroll", category: "Town", detail: "Cafés and mountain views.", ticketPriceUSD: 0, durationHours: 2, tip: nil),
                        ],
                        mealsHint: "Winelands lunch (~$35)", transportHint: "Organised wine tour from Cape Town"),
        ],
        tips: [
            "Domestic flight Johannesburg ↔ Cape Town saves a long drive.",
            "For safari, add Kruger or nearby private reserves for 2–3 nights.",
            "Cape Doctor wind can cancel Table Mountain — keep a flexible day.",
        ]
    )
}
