import Foundation
import MapKit
import Combine
import CoreLocation

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var searchQuery = "Dubai, United Arab Emirates"
    @Published var suggestions: [PlaceSearchResult] = []
    @Published var selectedPlace: PlaceSearchResult?
    @Published var selectedHotel: Hotel?
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708),
        span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.20)
    )
    @Published var routePolyline: MKPolyline?
    @Published var routeSteps: [MKRoute.Step] = []
    @Published var routeDistance: CLLocationDistance = 0
    @Published var routeExpectedTime: TimeInterval = 0
    @Published var isShowingRoute = false
    @Published var isNavigating = false
    @Published var isRoadRoute = false
    @Published var isLoadingHotels = false
    @Published var isCalculatingRoute = false
    @Published var directionsFailed = false
    @Published var routeSummary: String?
    @Published var placeContextSummary: String?
    @Published var navigationStatus: String?
    @Published var turnGuidance: TurnGuidance?
    @Published var vehicleCoordinate: CLLocationCoordinate2D?
    @Published var vehicleHeading: CLLocationDirection = 0
    @Published var hotels = SampleData.hotels
    @Published var spots = SampleData.spots
    @Published var destinationTitle = "Dubai, United Arab Emirates"

    let locationManager = LocationManager()

    private var searchTask: Task<Void, Never>?
    private var navigationTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private let completer = MKLocalSearchCompleter()
    private var completerDelegate: CompleterBridge?
    private var appleSuggestions: [PlaceSearchResult] = []

    init() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        setupCompleter()
    }

    var pins: [MapPin] {
        hotels.map { MapPin(kind: .hotel($0)) } + spots.map { MapPin(kind: .spot($0)) }
    }

    func onSearchQueryChanged(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            refreshSuggestions(for: query)
        }
        completer.queryFragment = query
    }

    func selectPlace(_ place: PlaceSearchResult) {
        if place.category == "Place", place.emoji == "📍" {
            geocodeAppleSuggestion(place)
            return
        }
        applySelection(place)
    }

    func submitSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let first = SearchCatalog.autocomplete(for: query).first {
            selectPlace(first)
            return
        }

        geocodeAppleSuggestion(
            PlaceSearchResult(
                id: UUID(),
                name: query,
                subtitle: "",
                category: "Place",
                emoji: "📍",
                latitude: 0,
                longitude: 0,
                priceLabel: nil,
                searchKeywords: [query.lowercased()]
            )
        )
    }

    private func geocodeAppleSuggestion(_ place: PlaceSearchResult) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [place.name, place.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")

        MKLocalSearch(request: request).start { [weak self] response, _ in
            Task { @MainActor in
                guard let self, let item = response?.mapItems.first else {
                    self?.placeContextSummary = "Place not found"
                    return
                }
                let city = item.placemark.locality ?? item.placemark.administrativeArea ?? place.subtitle
                let resolved = PlaceSearchResult(
                    id: UUID(),
                    name: item.name ?? place.name,
                    subtitle: place.subtitle.isEmpty ? city : place.subtitle,
                    category: place.category,
                    emoji: place.emoji == "📍" ? "📍" : place.emoji,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    priceLabel: place.priceLabel,
                    searchKeywords: place.searchKeywords
                )
                self.applySelection(resolved)
            }
        }
    }

    private func applySelection(_ place: PlaceSearchResult) {
        selectedPlace = place
        selectedHotel = nil
        searchQuery = place.subtitle.isEmpty ? place.name : "\(place.name), \(place.subtitle)"
        destinationTitle = searchQuery
        suggestions = []
        stopNavigation()
        clearRoute()

        mapRegion = MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )

        routeTask?.cancel()
        routeTask = Task {
            await loadHotelsAndStays(near: place)
        }
    }

    func selectHotel(_ hotel: Hotel) {
        selectedHotel = hotel
        selectedPlace = nil
        clearRoute()
    }

    func clearSelection() {
        selectedPlace = nil
        selectedHotel = nil
        placeContextSummary = nil
        clearRoute()
        hotels = SampleData.hotels
        spots = SampleData.spots
        mapRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708),
            span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.20)
        )
    }

    func startLiveNavigation() {
        guard let destination = selectedPlace?.coordinate ?? selectedHotel?.coordinate else { return }

        directionsFailed = false

        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            placeContextSummary = "Location access needed for in-app directions"
            directionsFailed = true
            return
        }

        routeTask?.cancel()
        routeTask = Task {
            isCalculatingRoute = true
            directionsFailed = false
            placeContextSummary = "Calculating road route…"
            navigationStatus = "Calculating route…"

            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }

            let source = await locationManager.awaitCurrentLocation()
            let route = await RouteService.calculateRoadRoute(
                from: source,
                to: destination,
                destinationName: selectedPlace?.name ?? selectedHotel?.name
            )

            isCalculatingRoute = false

            guard let route else {
                directionsFailed = true
                placeContextSummary = source == nil
                    ? "Waiting for GPS — enable location and try again"
                    : "Couldn't load route — check connection and try again"
                return
            }

            applyRoute(route, forNavigation: true)
            locationManager.startUpdating()
            isNavigating = true
            isShowingRoute = true
            placeContextSummary = nil
            updateVehiclePosition()
            startNavigationUpdates()
        }
    }

    func stopNavigation() {
        isNavigating = false
        navigationStatus = nil
        turnGuidance = nil
        navigationTimer?.invalidate()
        navigationTimer = nil
        if !isCalculatingRoute {
            clearRoute()
        }
    }

    func openInAppleMaps(destination: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        item.name = selectedPlace?.name ?? selectedHotel?.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func setupCompleter() {
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = mapRegion
        let bridge = CompleterBridge { [weak self] results in
            Task { @MainActor in
                self?.appleSuggestions = results
                if let query = self?.searchQuery {
                    self?.refreshSuggestions(for: query)
                }
            }
        }
        completerDelegate = bridge
        completer.delegate = bridge
    }

    private func refreshSuggestions(for query: String) {
        let local = SearchCatalog.autocomplete(for: query)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }

        var merged = local
        for apple in appleSuggestions where !merged.contains(where: { $0.name == apple.name }) {
            merged.append(apple)
        }
        suggestions = Array(merged.prefix(8))
    }

    private func loadHotelsAndStays(near place: PlaceSearchResult) async {
        isLoadingHotels = true
        placeContextSummary = "Finding hotels & rentals nearby…"

        let city = place.subtitle.isEmpty ? place.name : place.subtitle
        hotels = await HotelDiscovery.searchNear(
            coordinate: place.coordinate,
            city: city,
            placeName: place.name
        )

        if place.name.lowercased().contains("dubai") || city.lowercased().contains("dubai") {
            spots = SampleData.spots
        } else {
            spots = []
        }

        isLoadingHotels = false
        placeContextSummary = "\(hotels.count) stays nearby · tap a price pin"

        if let cheapest = hotels.min(by: { $0.pricePerNight < $1.pricePerNight }) {
            placeContextSummary = "\(hotels.count) stays from \(cheapest.priceLabel)/night"
        }
    }

    private func clearRoute() {
        routePolyline = nil
        routeSteps = []
        routeDistance = 0
        routeExpectedTime = 0
        isShowingRoute = false
        isRoadRoute = false
        routeSummary = nil
        vehicleCoordinate = nil
    }

    private func applyRoute(_ route: MKRoute, forNavigation: Bool) {
        routePolyline = route.polyline
        routeSteps = route.steps
        routeDistance = route.distance
        routeExpectedTime = route.expectedTravelTime
        isShowingRoute = true
        isRoadRoute = true

        let minutes = max(1, Int(route.expectedTravelTime / 60))
        let km = route.distance / 1000
        routeSummary = "\(minutes) min · \(String(format: "%.1f", km)) km by road"

        if forNavigation {
            fitRegionToPolyline(route.polyline)
            updateVehiclePosition()
            updateTurnGuidance()
        } else {
            fitRegionToPolyline(route.polyline)
        }
    }

    private func fitRegionToPolyline(_ polyline: MKPolyline) {
        let rect = polyline.boundingMapRect
        var region = MKCoordinateRegion(rect)
        region.span.latitudeDelta *= 1.35
        region.span.longitudeDelta *= 1.35
        mapRegion = region
    }

    private func updateVehiclePosition() {
        guard let polyline = routePolyline else { return }

        if let user = locationManager.userLocation {
            let snap = RouteGeometry.closestPoint(on: polyline, to: user)
            vehicleCoordinate = snap.coordinate
            vehicleHeading = snap.heading
            return
        }

        let start = RouteGeometry.coordinate(at: 0, on: polyline)
        vehicleCoordinate = start.coordinate
        vehicleHeading = start.heading
    }

    private func updateTurnGuidance() {
        guard let vehicle = vehicleCoordinate, !routeSteps.isEmpty else {
            turnGuidance = TurnGuidance(primary: "Head to destination", secondary: routeSummary, icon: "arrow.up")
            return
        }

        let guidance = RouteGeometry.guidance(at: vehicle, steps: routeSteps)
        let remaining = RouteGeometry.remainingDistance(from: vehicle, on: routePolyline!)
        let km = remaining / 1000
        let speed = max(routeDistance / max(routeExpectedTime, 1), 8)
        let etaMinutes = max(1, Int(remaining / speed / 60))
        let etaLine = String(format: "%.1f km · %d min remaining", km, etaMinutes)

        turnGuidance = TurnGuidance(
            primary: guidance.primary,
            secondary: guidance.secondary ?? etaLine,
            icon: guidance.icon
        )
        navigationStatus = guidance.primary
    }

    private func startNavigationUpdates() {
        navigationTimer?.invalidate()
        navigationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isNavigating, let polyline = self.routePolyline else { return }

                self.updateVehiclePosition()

                guard let vehicle = self.vehicleCoordinate else {
                    self.navigationStatus = "Waiting for GPS signal…"
                    return
                }

                let remaining = RouteGeometry.remainingDistance(from: vehicle, on: polyline)
                if remaining < 80 {
                    self.turnGuidance = TurnGuidance(primary: "You have arrived", secondary: nil, icon: "flag.checkered")
                    self.navigationStatus = "You have arrived!"
                    self.isNavigating = false
                    self.navigationTimer?.invalidate()
                    return
                }

                self.updateTurnGuidance()

                var region = self.mapRegion
                region.center = vehicle
                region.span = MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
                self.mapRegion = region
            }
        }
    }
}

private final class CompleterBridge: NSObject, MKLocalSearchCompleterDelegate {
    private let onUpdate: ([PlaceSearchResult]) -> Void

    init(onUpdate: @escaping ([PlaceSearchResult]) -> Void) {
        self.onUpdate = onUpdate
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.prefix(4).map { result in
            PlaceSearchResult(
                id: UUID(),
                name: result.title,
                subtitle: result.subtitle,
                category: "Place",
                emoji: "📍",
                latitude: 0,
                longitude: 0,
                priceLabel: nil,
                searchKeywords: [result.title, result.subtitle].map { $0.lowercased() }
            )
        }
        onUpdate(Array(mapped))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onUpdate([])
    }
}
