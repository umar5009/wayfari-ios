import CoreLocation

struct PlaceSearchResult: Identifiable, Hashable {
    let id: UUID
    let name: String
    let subtitle: String
    let category: String
    let emoji: String
    let latitude: Double
    let longitude: Double
    let priceLabel: String?
    let searchKeywords: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func == (lhs: PlaceSearchResult, rhs: PlaceSearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SearchCatalog {
    static let dubaiCity = PlaceSearchResult(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Dubai",
        subtitle: "United Arab Emirates",
        category: "City",
        emoji: "🇦🇪",
        latitude: 25.2048,
        longitude: 55.2708,
        priceLabel: nil,
        searchKeywords: ["dubai", "uae", "emirates", "dxb"]
    )

    static let lahoreCity = PlaceSearchResult(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Lahore",
        subtitle: "Pakistan",
        category: "City",
        emoji: "🇵🇰",
        latitude: 31.5497,
        longitude: 74.3436,
        priceLabel: nil,
        searchKeywords: ["lahore", "pakistan", "lhe"]
    )

    static let allPlaces: [PlaceSearchResult] = [
        dubaiCity,
        lahoreCity,
        place(from: SampleData.spots[0], price: "From AED 149"),
        place(from: SampleData.spots[1], price: "Free to explore"),
        place(from: SampleData.spots[2], price: "Museum AED 3"),
        place(from: SampleData.spots[3], price: "From AED 50"),
        place(from: SampleData.spots[4], price: "Free entry"),
        PlaceSearchResult(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "Dubai Creek Tower",
            subtitle: "Dubai Creek Harbour",
            category: "Landmark",
            emoji: "🏗️",
            latitude: 25.1950,
            longitude: 55.3480,
            priceLabel: "Under construction",
            searchKeywords: ["creek tower", "creek harbour", "dubai creek"]
        ),
        PlaceSearchResult(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: "Museum of the Future",
            subtitle: "Sheikh Zayed Road",
            category: "Museum",
            emoji: "🏛️",
            latitude: 25.2194,
            longitude: 55.2814,
            priceLabel: "From AED 149",
            searchKeywords: ["museum", "future", "motf"]
        ),
        PlaceSearchResult(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            name: "Dubai Frame",
            subtitle: "Zabeel Park",
            category: "Landmark",
            emoji: "🖼️",
            latitude: 25.2356,
            longitude: 55.3003,
            priceLabel: "From AED 50",
            searchKeywords: ["frame", "zabeel"]
        ),
        PlaceSearchResult(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            name: "Dubai Marina",
            subtitle: "Marina Walk",
            category: "District",
            emoji: "⛵",
            latitude: 25.0805,
            longitude: 55.1403,
            priceLabel: "Free to explore",
            searchKeywords: ["marina", "yacht", "walk"]
        ),
        PlaceSearchResult(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            name: "Jumeirah Mosque",
            subtitle: "Jumeirah Beach Road",
            category: "Heritage",
            emoji: "🕌",
            latitude: 25.2339,
            longitude: 55.2600,
            priceLabel: "From AED 25",
            searchKeywords: ["mosque", "jumeirah"]
        ),
        PlaceSearchResult(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            name: "Dubai Aquarium",
            subtitle: "Dubai Mall",
            category: "Attraction",
            emoji: "🐠",
            latitude: 25.1975,
            longitude: 55.2796,
            priceLabel: "From AED 169",
            searchKeywords: ["aquarium", "underwater"]
        ),
        hotelPlace(from: SampleData.hotels[0]),
        hotelPlace(from: SampleData.hotels[1]),
        hotelPlace(from: SampleData.hotels[2]),
        hotelPlace(from: SampleData.hotels[4]),
    ]

    static func autocomplete(for rawQuery: String) -> [PlaceSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        let scored = allPlaces.compactMap { place -> (PlaceSearchResult, Int)? in
            let score = matchScore(for: place, query: query)
            return score > 0 ? (place, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)

        if query.contains("dubai") || query == "uae" || query.contains("emirates") {
            let cityFirst = [dubaiCity] + scored.filter { $0.id != dubaiCity.id }
            return Array(cityFirst.prefix(8))
        }

        if query.contains("lahore") || query.contains("pakistan") {
            let cityFirst = [lahoreCity] + scored.filter { $0.id != lahoreCity.id }
            return Array(cityFirst.prefix(8))
        }

        return Array(scored.prefix(8))
    }

    private static func place(from spot: SightSpot, price: String) -> PlaceSearchResult {
        PlaceSearchResult(
            id: spot.id,
            name: spot.name,
            subtitle: spot.neighbourhood,
            category: spot.category,
            emoji: spot.emoji,
            latitude: spot.latitude,
            longitude: spot.longitude,
            priceLabel: price,
            searchKeywords: [spot.name, spot.category, spot.neighbourhood, "dubai"]
                .map { $0.lowercased() }
        )
    }

    private static func hotelPlace(from hotel: Hotel) -> PlaceSearchResult {
        PlaceSearchResult(
            id: hotel.id,
            name: hotel.name,
            subtitle: hotel.neighbourhood,
            category: "Hotel",
            emoji: hotel.emoji,
            latitude: hotel.latitude,
            longitude: hotel.longitude,
            priceLabel: hotel.priceLabel + "/night",
            searchKeywords: [hotel.name, hotel.neighbourhood, hotel.city, "hotel"]
                .map { $0.lowercased() }
        )
    }

    private static func matchScore(for place: PlaceSearchResult, query: String) -> Int {
        var score = 0
        let name = place.name.lowercased()
        let subtitle = place.subtitle.lowercased()

        if name == query { score += 100 }
        if name.hasPrefix(query) { score += 80 }
        if name.contains(query) { score += 60 }
        if subtitle.contains(query) { score += 40 }

        for keyword in place.searchKeywords {
            if keyword.hasPrefix(query) { score += 50 }
            if keyword.contains(query) { score += 30 }
            if query.contains(keyword) && keyword.count > 3 { score += 20 }
        }

        return score
    }
}
