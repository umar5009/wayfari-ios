import Foundation
import MapKit
import CoreLocation

enum HotelDiscovery {
    private static let emojis = ["🏨", "🏩", "🏰", "🌃", "🛏️", "🌊"]

    static func searchNear(coordinate: CLLocationCoordinate2D, city: String, placeName: String) async -> [Hotel] {
        var hotels = await searchMapKitHotels(near: coordinate, city: city)

        if hotels.count < 5 {
            let existing = Set(hotels.map(\.name))
            let synthetic = syntheticHotels(
                near: coordinate,
                city: city,
                area: placeName,
                count: max(6 - hotels.count, 0)
            ).filter { !existing.contains($0.name) }
            hotels.append(contentsOf: synthetic)
        }

        return Array(hotels.prefix(8))
    }

    private static func searchMapKitHotels(near coordinate: CLLocationCoordinate2D, city: String) async -> [Hotel] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "hotel"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 10_000,
            longitudinalMeters: 10_000
        )
        request.resultTypes = .pointOfInterest

        let response: MKLocalSearch.Response? = await withCheckedContinuation { continuation in
            MKLocalSearch(request: request).start { response, _ in
                continuation.resume(returning: response)
            }
        }

        guard let items = response?.mapItems, !items.isEmpty else { return [] }

        return items.prefix(8).enumerated().map { index, item in
            mapItemToHotel(item, city: city, index: index)
        }
    }

    private static func mapItemToHotel(_ item: MKMapItem, city: String, index: Int) -> Hotel {
        let name = item.name ?? "Hotel \(index + 1)"
        let coordinate = item.placemark.coordinate
        let neighbourhood = item.placemark.subLocality
            ?? item.placemark.locality
            ?? city
        let seed = abs(name.hashValue)
        let stars = 3 + (seed % 3)
        let price = 45 + (seed % 280)

        return Hotel(
            name: name,
            neighbourhood: neighbourhood,
            city: city,
            stars: stars,
            rating: Double(75 + (seed % 23)) / 10,
            reviewCount: 400 + (seed % 5000),
            pricePerNight: price,
            amenities: ["WiFi", "Breakfast", "Parking"],
            emoji: emojis[index % emojis.count],
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private static func syntheticHotels(
        near center: CLLocationCoordinate2D,
        city: String,
        area: String,
        count: Int
    ) -> [Hotel] {
        guard count > 0 else { return [] }

        let templates: [(String, Int, Int)] = [
            ("Grand \(area) Hotel", 5, 189),
            ("\(city) Central Inn", 4, 95),
            ("Comfort Stay \(area)", 3, 62),
            ("Luxury Suites \(city)", 5, 240),
            ("Budget Lodge", 3, 48),
            ("Riverside Hotel", 4, 118),
        ]

        return templates.prefix(count).enumerated().map { index, template in
            let angle = Double(index) * (.pi * 2 / Double(max(count, 1)))
            let radius = 0.012 + Double(index) * 0.004
            let lat = center.latitude + cos(angle) * radius
            let lon = center.longitude + sin(angle) * radius

            return Hotel(
                name: template.0,
                neighbourhood: area,
                city: city,
                stars: template.1,
                rating: Double(78 + index * 3) / 10,
                reviewCount: 900 + index * 400,
                pricePerNight: template.2 + index * 12,
                amenities: ["WiFi", "Pool", "Restaurant"],
                emoji: emojis[index % emojis.count],
                latitude: lat,
                longitude: lon
            )
        }
    }
}

enum RouteService {
    @MainActor
    static func calculateRoadRoute(
        from source: CLLocationCoordinate2D?,
        to destination: CLLocationCoordinate2D,
        destinationName: String?
    ) async -> MKRoute? {
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        destinationItem.name = destinationName ?? "Destination"

        if let source {
            let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: source))
            sourceItem.name = "My Location"

            for transport: MKDirectionsTransportType in [.automobile, .any] {
                if let route = await calculate(from: sourceItem, to: destinationItem, transport: transport) {
                    return route
                }
            }
        }

        for transport: MKDirectionsTransportType in [.automobile, .any] {
            if let route = await calculateFromCurrentLocation(to: destinationItem, transport: transport) {
                return route
            }
        }

        return nil
    }

    @MainActor
    private static func calculate(
        from source: MKMapItem,
        to destination: MKMapItem,
        transport: MKDirectionsTransportType
    ) async -> MKRoute? {
        await withCheckedContinuation { continuation in
            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = transport
            request.requestsAlternateRoutes = false

            MKDirections(request: request).calculate { response, _ in
                continuation.resume(returning: response?.routes.first)
            }
        }
    }

    @MainActor
    private static func calculateFromCurrentLocation(
        to destination: MKMapItem,
        transport: MKDirectionsTransportType
    ) async -> MKRoute? {
        await withCheckedContinuation { continuation in
            let request = MKDirections.Request()
            request.source = MKMapItem.forCurrentLocation()
            request.destination = destination
            request.transportType = transport
            request.requestsAlternateRoutes = false

            MKDirections(request: request).calculate { response, _ in
                continuation.resume(returning: response?.routes.first)
            }
        }
    }
}
