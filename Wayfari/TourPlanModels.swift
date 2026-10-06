import Foundation
import CoreLocation

// MARK: - Parsed / draft request from voice / text
struct TourRequest: Equatable {
    var destinations: [String]
    /// Nil until the user specifies duration — never silently default.
    var days: Int?
    var travelers: Int?
    var budgetHint: String?
    /// Departure country is required so flight routes are not guessed.
    var originCountry: String?
    /// Preferred departure city when the user named one (e.g. Lahore).
    var originCity: String?
    var rawQuery: String

    var title: String {
        let dest = destinations.isEmpty ? "Your trip" : destinations.joined(separator: " · ")
        if let days {
            return "\(dest) · \(days) days"
        }
        return dest
    }

    var nights: Int {
        guard let days else { return 1 }
        return max(days - 1, 1)
    }

    /// Fields still needed before a full package can be built.
    var missingRequirements: [TourMissingField] {
        var missing: [TourMissingField] = []
        if destinations.isEmpty { missing.append(.destination) }
        if days == nil { missing.append(.days) }
        if originCountry == nil { missing.append(.originCountry) }
        return missing
    }

    var isComplete: Bool { missingRequirements.isEmpty }

    /// Ready for `TourPlanGenerator.generate` — days & destination guaranteed.
    func resolved() -> TourRequest? {
        guard let days, !destinations.isEmpty, originCountry != nil else { return nil }
        return TourRequest(
            destinations: destinations,
            days: days,
            travelers: travelers ?? 2,
            budgetHint: budgetHint,
            originCountry: originCountry,
            originCity: originCity,
            rawQuery: rawQuery
        )
    }

    mutating func merge(from other: TourRequest) {
        if !other.destinations.isEmpty { destinations = other.destinations }
        if let d = other.days { days = d }
        if let t = other.travelers { travelers = t }
        if let b = other.budgetHint { budgetHint = b }
        if let country = other.originCountry { originCountry = country }
        if let city = other.originCity { originCity = city }
        if !other.rawQuery.isEmpty { rawQuery = other.rawQuery }
    }

    static var empty: TourRequest {
        TourRequest(
            destinations: [], days: nil, travelers: nil, budgetHint: nil,
            originCountry: nil, originCity: nil, rawQuery: ""
        )
    }
}

enum TourMissingField: Equatable {
    case destination
    case days
    case originCountry

    var prompt: String {
        switch self {
        case .destination:
            return "Which country or region would you like to visit? You can say one place (e.g. Japan) or a combo (e.g. Canada and USA)."
        case .days:
            return "How many days do you want to spend there? For example: 5 days, 7 days, or 10 days."
        case .originCountry:
            return "Which city or country are you departing from? For example: Lahore, Karachi, Delhi, or Pakistan."
        }
    }

    var shortPrompt: String {
        switch self {
        case .destination: return "Which destination?"
        case .days: return "How many days?"
        case .originCountry: return "Which departure city/country?"
        }
    }
}

// MARK: - Full tour plan response
struct TourPlan: Identifiable {
    let id = UUID()
    let request: TourRequest
    let summary: String
    let bestSeason: String
    let currency: String
    let visaNote: String
    let estimatedBudgetMin: Int
    let estimatedBudgetMax: Int
    let flights: [TourFlightOption]
    let hotels: [TourHotelOption]
    let days: [ItineraryDay]
    let routeStops: [TourRouteStop]
    let placePins: [TourPlacePin]
    let tips: [String]
}

/// An itinerary place shown as a priced pin on the journey map.
struct TourPlacePin: Identifiable, Hashable {
    let id = UUID()
    let dayNumber: Int
    let name: String
    let city: String
    let category: String
    let ticketPriceUSD: Int?
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var priceLabel: String {
        guard let ticketPriceUSD, ticketPriceUSD > 0 else { return "Free" }
        return "$\(ticketPriceUSD)"
    }
}

/// One stop on the guided journey map (home → destinations → home).
struct TourRouteStop: Identifiable, Hashable {
    let id = UUID()
    let order: Int
    let city: String
    let country: String
    let kind: Kind
    let latitude: Double
    let longitude: Double
    let detail: String

    enum Kind: String {
        case departure = "Departure"
        case arrival = "Arrival"
        case internalStop = "City stop"
        case returnHome = "Return home"

        var systemImage: String {
            switch self {
            case .departure: return "house.fill"
            case .arrival: return "airplane.arrival"
            case .internalStop: return "mappin.circle.fill"
            case .returnHome: return "airplane.departure"
            }
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Flight option (budget → luxury)
enum FlightCabinTier: String, CaseIterable {
    case budget = "Cheapest"
    case value = "Best Value"
    case premium = "Premium"
    case luxury = "Luxury"

    var icon: String {
        switch self {
        case .budget:  return "airplane"
        case .value:   return "airplane.circle"
        case .premium: return "star.circle"
        case .luxury:  return "crown.fill"
        }
    }
}

struct TourFlightOption: Identifiable {
    let id = UUID()
    let tier: FlightCabinTier
    let originCity: String
    let originCode: String
    let airline: String
    let iataCode: String
    let route: String
    let cabin: String
    let duration: String
    let stops: String
    let departure: String
    let arrival: String
    let priceUSD: Int
    let notes: String
}

// MARK: - Hotel option (3★ → 5★)
struct TourHotelOption: Identifiable {
    let id = UUID()
    let name: String
    let city: String
    let neighbourhood: String
    let stars: Int
    let rating: Double
    let pricePerNight: Int
    let amenities: [String]
    let style: String
}

// MARK: - Day-by-day itinerary
struct ItineraryDay: Identifiable {
    let id = UUID()
    let dayNumber: Int
    let title: String
    let city: String
    let theme: String
    let activities: [ItineraryActivity]
    let mealsHint: String
    let transportHint: String

    var dayTicketsTotal: Int {
        activities.reduce(0) { $0 + ($1.ticketPriceUSD ?? 0) }
    }
}

struct ItineraryActivity: Identifiable {
    let id = UUID()
    let time: String
    let name: String
    let category: String
    let detail: String
    let ticketPriceUSD: Int?
    let durationHours: Double
    let tip: String?

    var ticketLabel: String {
        guard let ticketPriceUSD else { return "Free" }
        return ticketPriceUSD == 0 ? "Free" : "$\(ticketPriceUSD)"
    }
}
