import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var oneShotContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func awaitCurrentLocation(timeoutSeconds: Double = 6) async -> CLLocationCoordinate2D? {
        if let userLocation { return userLocation }

        startUpdating()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let userLocation { return userLocation }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        return await requestOneShotLocation()
    }

    private func requestOneShotLocation() async -> CLLocationCoordinate2D? {
        if let userLocation { return userLocation }

        return await withCheckedContinuation { continuation in
            oneShotContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate

        if let continuation = oneShotContinuation {
            oneShotContinuation = nil
            continuation.resume(returning: location.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let continuation = oneShotContinuation {
            oneShotContinuation = nil
            continuation.resume(returning: userLocation)
        }
    }
}
