import Foundation
import CoreLocation

// MARK: - Hotel
struct Hotel: Identifiable, Hashable {
    let id: UUID = UUID()
    let name: String
    let neighbourhood: String
    let city: String
    let stars: Int
    let rating: Double
    let reviewCount: Int
    let pricePerNight: Int
    let amenities: [String]
    let emoji: String
    let latitude: Double
    let longitude: Double
    var isFavourite: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var priceLabel: String { "$\(pricePerNight)" }
    var starsText: String { String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars) }
    var ratingText: String { String(format: "%.1f · %dk reviews", rating, reviewCount / 1000) }

    static func == (lhs: Hotel, rhs: Hotel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Flight segment
struct FlightSegment: Identifiable, Hashable {
    let id: UUID = UUID()
    let airline: String
    let iataCode: String
    let flightNumber: String
    let originCode: String
    let originCity: String
    let destinationCode: String
    let destinationCity: String
    let departure: String
    let arrival: String
    let durationMinutes: Int
    let layoverMinutes: Int?

    var durationLabel: String {
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var layoverLabel: String? {
        guard let layoverMinutes, layoverMinutes > 0 else { return nil }
        let h = layoverMinutes / 60
        let m = layoverMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m layover" }
        if h > 0 { return "\(h)h layover" }
        return "\(m)m layover"
    }
}

// MARK: - Flight
struct Flight: Identifiable, Hashable {
    let id: UUID = UUID()
    let airline: String
    let iataCode: String
    let originCity: String
    let originCode: String
    let destinationCity: String
    let destinationCode: String
    let departure: String
    let arrival: String
    let duration: String
    let durationMinutes: Int
    let stops: Int
    let cabinClass: String
    let priceUSD: Int
    let returnDeparture: String?
    let returnArrival: String?
    let returnDurationMinutes: Int?
    let outboundSegments: [FlightSegment]
    let returnSegments: [FlightSegment]

    var stopsLabel: String { stops == 0 ? "Non-stop" : "\(stops) Stop\(stops > 1 ? "s" : "")" }
    var priceLabel: String { "$\(priceUSD)" }

    var outboundAirlineCodes: [String] { uniqueAirlineCodes(from: outboundSegments) }
    var returnAirlineCodes: [String] { uniqueAirlineCodes(from: returnSegments) }
    var allAirlineCodes: [String] { uniqueAirlineCodes(from: outboundSegments + returnSegments) }

    private func uniqueAirlineCodes(from segments: [FlightSegment]) -> [String] {
        var seen = Set<String>()
        return segments.compactMap { segment in
            guard seen.insert(segment.iataCode).inserted else { return nil }
            return segment.iataCode
        }
    }

    init(
        airline: String,
        iataCode: String,
        originCity: String,
        originCode: String,
        destinationCity: String,
        destinationCode: String,
        departure: String,
        arrival: String,
        duration: String,
        durationMinutes: Int,
        stops: Int,
        cabinClass: String,
        priceUSD: Int,
        returnDeparture: String? = nil,
        returnArrival: String? = nil,
        returnDurationMinutes: Int? = nil,
        outboundSegments: [FlightSegment]? = nil,
        returnSegments: [FlightSegment]? = nil
    ) {
        self.airline = airline
        self.iataCode = iataCode
        self.originCity = originCity
        self.originCode = originCode
        self.destinationCity = destinationCity
        self.destinationCode = destinationCode
        self.departure = departure
        self.arrival = arrival
        self.duration = duration
        self.durationMinutes = durationMinutes
        self.stops = stops
        self.cabinClass = cabinClass
        self.priceUSD = priceUSD
        self.returnDeparture = returnDeparture
        self.returnArrival = returnArrival
        self.returnDurationMinutes = returnDurationMinutes

        let defaultOutbound = FlightSegment(
            airline: airline,
            iataCode: iataCode,
            flightNumber: "\(iataCode)101",
            originCode: originCode,
            originCity: originCity,
            destinationCode: destinationCode,
            destinationCity: destinationCity,
            departure: departure,
            arrival: arrival,
            durationMinutes: durationMinutes,
            layoverMinutes: nil
        )
        self.outboundSegments = outboundSegments ?? [defaultOutbound]

        if let returnDeparture, let returnArrival, let returnDurationMinutes {
            let defaultReturn = FlightSegment(
                airline: airline,
                iataCode: iataCode,
                flightNumber: "\(iataCode)201",
                originCode: destinationCode,
                originCity: destinationCity,
                destinationCode: originCode,
                destinationCity: originCity,
                departure: returnDeparture,
                arrival: returnArrival,
                durationMinutes: returnDurationMinutes,
                layoverMinutes: nil
            )
            self.returnSegments = returnSegments ?? [defaultReturn]
        } else {
            self.returnSegments = returnSegments ?? []
        }
    }

    static func == (lhs: Flight, rhs: Flight) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - SightSeeing Spot
struct SightSpot: Identifiable {
    let id: UUID = UUID()
    let name: String
    let category: String
    let emoji: String
    let neighbourhood: String
    let rating: Double
    let visitCount: String
    let about: String
    let tips: String
    let facts: [(value: String, label: String)]
    let photoEmojis: [String]
    let gradientStart: String
    let gradientEnd: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Travel Package
struct TravelPackage: Identifiable {
    let id: UUID = UUID()
    let tier: PackageTier
    let name: String
    let pricePerPerson: Int
    let nights: Int
    let items: [PackageLineItem]
}

enum PackageTier: String, CaseIterable {
    case luxury  = "5-Star Luxury"
    case comfort = "4-Star Comfort"
    case budget  = "3-Star Budget"

    var stars: String {
        switch self { case .luxury: return "★★★★★"; case .comfort: return "★★★★"; case .budget: return "★★★" }
    }
    var badgeText: String { "\(stars)  \(rawValue)" }
}

struct PackageLineItem: Identifiable {
    let id: UUID = UUID()
    let icon: String
    let name: String
    let detail: String
    let price: Int
}

// MARK: - Chat
struct ChatMessage: Identifiable {
    let id: UUID = UUID()
    let role: MessageRole
    let text: String
}

enum MessageRole { case bot, user }

// MARK: - Recent Search
struct RecentItem: Identifiable {
    let id: UUID = UUID()
    let emoji: String
    let title: String
    let subtitle: String
    let price: String
    let timeAgo: String
}

// MARK: - Sample Data
enum SampleData {

    // MARK: Hotels
    static let hotels: [Hotel] = [
        Hotel(name: "Burj Al Arab Jumeirah", neighbourhood: "Jumeirah Beach", city: "Dubai", stars: 5, rating: 9.8, reviewCount: 4200, pricePerNight: 320, amenities: ["Sea View", "Infinity Pool", "Butler", "Helipad"], emoji: "🏰", latitude: 25.1412, longitude: 55.1853),
        Hotel(name: "Atlantis The Palm",     neighbourhood: "Palm Jumeirah",   city: "Dubai", stars: 5, rating: 9.5, reviewCount: 6100, pricePerNight: 210, amenities: ["Waterpark", "Private Beach", "Aquarium"],        emoji: "🌊", latitude: 25.1304, longitude: 55.1173),
        Hotel(name: "JW Marriott Marquis",   neighbourhood: "Business Bay",    city: "Dubai", stars: 4, rating: 9.1, reviewCount: 3800, pricePerNight: 145, amenities: ["Spa", "City View", "Gym", "Pool"],              emoji: "🏩", latitude: 25.1868, longitude: 55.2690),
        Hotel(name: "ibis Dubai Al Barsha",  neighbourhood: "Al Barsha",       city: "Dubai", stars: 3, rating: 8.4, reviewCount: 2100, pricePerNight: 67,  amenities: ["Metro Access", "Free WiFi", "24h Front Desk"],  emoji: "🏨", latitude: 25.1141, longitude: 55.1975),
        Hotel(name: "Address Downtown",      neighbourhood: "Downtown Dubai",  city: "Dubai", stars: 5, rating: 9.6, reviewCount: 5200, pricePerNight: 89,  amenities: ["Burj View", "Rooftop Pool", "Fine Dining"],     emoji: "🌃", latitude: 25.1924, longitude: 55.2799),
    ]

    // MARK: Flights
    static let flights: [Flight] = [
        Flight(airline: "Pakistan Int'l Airlines", iataCode: "PK", originCity: "Karachi", originCode: "KHI", destinationCity: "Dubai", destinationCode: "DXB", departure: "06:30", arrival: "08:15", duration: "2h 45m", durationMinutes: 165, stops: 0, cabinClass: "Economy",  priceUSD: 189),
        Flight(airline: "Emirates",                iataCode: "EK", originCity: "Karachi", originCode: "KHI", destinationCity: "Dubai", destinationCode: "DXB", departure: "10:00", arrival: "11:50", duration: "2h 50m", durationMinutes: 170, stops: 0, cabinClass: "Business", priceUSD: 620),
        Flight(airline: "flydubai",                iataCode: "FZ", originCity: "Karachi", originCode: "KHI", destinationCity: "Dubai", destinationCode: "DXB", departure: "14:20", arrival: "17:15", duration: "2h 55m", durationMinutes: 175, stops: 0, cabinClass: "Economy",  priceUSD: 149),
        Flight(airline: "Air Arabia",              iataCode: "G9", originCity: "Karachi", originCode: "KHI", destinationCity: "Sharjah", destinationCode: "SHJ", departure: "18:45", arrival: "20:30", duration: "2h 45m", durationMinutes: 165, stops: 0, cabinClass: "Economy", priceUSD: 112),
        Flight(airline: "Qatar Airways",           iataCode: "QR", originCity: "Karachi", originCode: "KHI", destinationCity: "Dubai", destinationCode: "DXB", departure: "22:10", arrival: "02:05", duration: "3h 55m", durationMinutes: 235, stops: 1, cabinClass: "Business", priceUSD: 890),
    ]

    // MARK: Sightseeing
    static let spots: [SightSpot] = [
        SightSpot(
            name: "Burj Khalifa", category: "Landmark", emoji: "🗼",
            neighbourhood: "Downtown Dubai", rating: 4.9, visitCount: "82k",
            about: "At 828 metres, the Burj Khalifa is the world's tallest structure. Designed by Skidmore, Owings & Merrill and opened in January 2010, its silhouette was inspired by the Hymenocallis flower and Islamic geometry. Observation decks on floors 124 and 148 deliver panoramic views over the Gulf and the desert.",
            tips: "Pre-book 'At the Top' tickets online — queues at the desk are long. Sunset visits around 6:30 pm are magical, and the Dubai Fountain show starts directly below every 30 minutes from dusk.",
            facts: [("828 m", "Height"), ("2010", "Opened"), ("163", "Floors")],
            photoEmojis: ["🌃", "🌅", "🌆", "✨"],
            gradientStart: "#8B5E3C", gradientEnd: "#5C3A20",
            latitude: 25.1972, longitude: 55.2744
        ),
        SightSpot(
            name: "Palm Jumeirah", category: "Island", emoji: "🌴",
            neighbourhood: "Palm Jumeirah Island", rating: 4.8, visitCount: "45k",
            about: "The world's largest artificial island was built between 2001–2006 using 94 million m³ of sand. Shaped like a palm with 16 fronds, it hosts 40+ luxury hotels and is visible from space. The Palm Monorail connects the trunk to the Atlantis hotel at the tip.",
            tips: "Take the Palm Monorail for scenic views. Sunset from Atlantis's observation deck is spectacular. Nakheel Mall on the trunk has excellent waterfront dining.",
            facts: [("5.7 km", "Length"), ("2006", "Completed"), ("40+", "Hotels")],
            photoEmojis: ["🏝️", "🌊", "🏰", "🌙"],
            gradientStart: "#2E5B8A", gradientEnd: "#1A3558",
            latitude: 25.1121, longitude: 55.1390
        ),
        SightSpot(
            name: "Al Fahidi District", category: "Heritage", emoji: "🕌",
            neighbourhood: "Bur Dubai", rating: 4.7, visitCount: "38k",
            about: "Dubai's oldest neighbourhood dates to 1890. Coral and gypsum buildings with distinctive wind towers (barjeel) pre-date air conditioning. Today the area houses the Dubai Museum, art galleries, boutique hotels, and the Creek where traditional abra boats still ferry passengers.",
            tips: "Dubai Museum admission is just AED 3. Take an abra across the Creek to the Gold and Spice Souks. Late-afternoon light is ideal for photography in the winding alleyways.",
            facts: [("1890", "Founded"), ("AED 3", "Museum entry"), ("1 km", "To Creek")],
            photoEmojis: ["🏺", "🕌", "🛶", "🌅"],
            gradientStart: "#5C3A8A", gradientEnd: "#38205C",
            latitude: 25.2631, longitude: 55.2970
        ),
        SightSpot(
            name: "Dubai Safari Park", category: "Adventure", emoji: "🦁",
            neighbourhood: "Al Warqa'a", rating: 4.6, visitCount: "28k",
            about: "Opened in 2017 across 119 hectares, Dubai Safari Park houses 3,000+ animals of 78 species in four zones: Arabian, Asian, African, and Kids Farm. Active conservation programmes protect endangered regional species.",
            tips: "Book online for a 15 % discount. The African Village has the best big-cat sightings. Arrive at 9 am — animals are far more active in the cooler morning hours.",
            facts: [("119 ha", "Area"), ("3,000+", "Animals"), ("78", "Species")],
            photoEmojis: ["🦁", "🐘", "🦒", "🌿"],
            gradientStart: "#2E8A5B", gradientEnd: "#1A5C38",
            latitude: 25.1536, longitude: 55.4132
        ),
        SightSpot(
            name: "Dubai Mall", category: "Shopping", emoji: "🛍️",
            neighbourhood: "Downtown Dubai", rating: 4.8, visitCount: "120k",
            about: "The world's largest mall by total area covers 5.9 million sq ft. With 1,200+ stores, a 10-million-litre aquarium, an Olympic ice rink, VR park, and a 30 m indoor waterfall, it draws over 100 million visitors a year — more than many capital cities.",
            tips: "Enter via the Burj Khalifa skybridge for tower views. The Aquarium ticket is worth it. The Dubai Fountain show runs every 30 minutes from 6 pm on the outdoor promenade.",
            facts: [("1,200+", "Stores"), ("100 M+", "Annual visits"), ("5.9 M ft²", "Area")],
            photoEmojis: ["🛒", "🎿", "🐟", "💎"],
            gradientStart: "#8A2E2E", gradientEnd: "#5C1A1A",
            latitude: 25.1980, longitude: 55.2796
        ),
    ]

    // MARK: Packages
    static func packages(country: String, budget: String) -> [TravelPackage] {
        [
            TravelPackage(tier: .luxury,  name: "\(country) Diamond Escape",    pricePerPerson: 3800, nights: 5, items: [
                PackageLineItem(icon: "airplane",          name: "Return Flight · Business Class", detail: "KHI ↔ DXB · Emirates",          price: 620),
                PackageLineItem(icon: "building.2",        name: "Burj Al Arab · 5 nights",        detail: "Ocean Suite · Breakfast included", price: 1600),
                PackageLineItem(icon: "car.fill",          name: "Private Airport Transfer",       detail: "Luxury sedan · Both ways",        price: 120),
                PackageLineItem(icon: "fork.knife",        name: "Fine Dining · 3 restaurants",    detail: "Nobu · Pierchic · At.mosphere",   price: 450),
                PackageLineItem(icon: "tram.fill",         name: "City Tours + Metro Pass",        detail: "Dubai Frame · Palm · Creek",      price: 200),
            ]),
            TravelPackage(tier: .comfort, name: "\(country) Classic Experience", pricePerPerson: 1800, nights: 5, items: [
                PackageLineItem(icon: "airplane",          name: "Return Flight · Economy",        detail: "KHI ↔ DXB · flydubai",           price: 149),
                PackageLineItem(icon: "building.2",        name: "JW Marriott · 5 nights",         detail: "Superior Room · Breakfast",       price: 725),
                PackageLineItem(icon: "car.fill",          name: "Shared Airport Transfer",        detail: "Taxi · Both ways",                price: 50),
                PackageLineItem(icon: "fork.knife",        name: "Local Dining Budget",            detail: "Restaurant recommendations",      price: 250),
                PackageLineItem(icon: "tram.fill",         name: "Metro + Bus Pass · 5 days",      detail: "Nol Red Card · City access",      price: 30),
            ]),
            TravelPackage(tier: .budget,  name: "\(country) Smart Saver",        pricePerPerson: 780,  nights: 5, items: [
                PackageLineItem(icon: "airplane",          name: "Return Flight · Economy",        detail: "KHI ↔ DXB · PIA",                price: 189),
                PackageLineItem(icon: "building.2",        name: "ibis Al Barsha · 5 nights",      detail: "Standard Room",                   price: 335),
                PackageLineItem(icon: "bus.fill",          name: "Public Bus Transfer",            detail: "RTA Bus · Both ways",             price: 4),
                PackageLineItem(icon: "fork.knife",        name: "Street Food + Cafes",            detail: "Shawarma · Local spots",          price: 100),
                PackageLineItem(icon: "tram.fill",         name: "Metro Pass · 5 days",            detail: "Nol Silver Card",                 price: 20),
            ]),
        ]
    }

    // MARK: Recents
    static let recents: [RecentItem] = [
        RecentItem(emoji: "✈️", title: "KHI → DXB · Economy",      subtitle: "flydubai · 15 May",       price: "$149",       timeAgo: "2h ago"),
        RecentItem(emoji: "🏰", title: "Burj Al Arab Jumeirah",     subtitle: "Dubai · 15–18 May",       price: "$320/night", timeAgo: "2h ago"),
        RecentItem(emoji: "🗺️", title: "Dubai, UAE",                subtitle: "5 nights · 2 adults",    price: "$1,240",     timeAgo: "Yesterday"),
        RecentItem(emoji: "🏩", title: "JW Marriott Marquis",       subtitle: "Business Bay · Jun 2–5", price: "$145/night", timeAgo: "3 days ago"),
        RecentItem(emoji: "✈️", title: "KHI → ISB · Economy",      subtitle: "PIA · 20 May",            price: "$89",        timeAgo: "3 days ago"),
        RecentItem(emoji: "🌴", title: "Istanbul, Turkey",           subtitle: "7 nights · 2 adults",   price: "$980",       timeAgo: "Last week"),
    ]
}
