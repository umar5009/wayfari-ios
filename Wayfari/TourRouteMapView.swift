import SwiftUI
import MapKit

/// MapKit itinerary map: home → arrival → internal cities → home, plus every
/// itinerary place pinned with its ticket price.
struct TourRouteMapView: UIViewRepresentable {
    enum FitTarget: Hashable {
        case journey
        case places
    }

    let stops: [TourRouteStop]
    let placePins: [TourPlacePin]
    let fitTarget: FitTarget

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.register(PlacePricePinView.self, forAnnotationViewWithReuseIdentifier: PlacePricePinView.reuseID)
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(on: mapView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TourRouteMapView
        private var syncedSignature: String?
        private var fittedTarget: FitTarget?

        init(_ parent: TourRouteMapView) { self.parent = parent }

        func sync(on mapView: MKMapView) {
            let signature = parent.stops.map { "\($0.order)-\($0.city)" }.joined(separator: "|")
                + "#" + parent.placePins.map(\.name).joined(separator: "|")

            let isNewData = signature != syncedSignature
            if isNewData {
                syncedSignature = signature
                fittedTarget = nil
                mapView.removeAnnotations(mapView.annotations)
                mapView.removeOverlays(mapView.overlays)

                mapView.addAnnotations(parent.stops.map { RouteStopAnnotation(stop: $0) })
                mapView.addAnnotations(parent.placePins.map { PlacePinAnnotation(pin: $0) })

                var coords = parent.stops.map(\.coordinate)
                if coords.count >= 2 {
                    mapView.addOverlay(MKPolyline(coordinates: &coords, count: coords.count))
                }
            }

            guard fittedTarget != parent.fitTarget else { return }
            fittedTarget = parent.fitTarget
            fit(mapView, animated: !isNewData)
        }

        private func fit(_ mapView: MKMapView, animated: Bool) {
            let coords: [CLLocationCoordinate2D]
            switch parent.fitTarget {
            case .journey:
                coords = parent.stops.map(\.coordinate)
            case .places:
                let pins = parent.placePins.map(\.coordinate)
                coords = pins.isEmpty ? parent.stops.map(\.coordinate) : pins
            }
            guard !coords.isEmpty else { return }
            mapView.setVisibleMapRect(
                routeRect(for: coords),
                edgePadding: UIEdgeInsets(top: 56, left: 44, bottom: 44, right: 44),
                animated: animated
            )
        }

        private func routeRect(for coords: [CLLocationCoordinate2D]) -> MKMapRect {
            var rect = MKMapRect.null
            for coord in coords {
                let point = MKMapPoint(coord)
                let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
                rect = rect.isNull ? pointRect : rect.union(pointRect)
            }
            return rect
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = 3.5
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let stopAnnotation = annotation as? RouteStopAnnotation {
                let id = "tourRouteStop"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = true
                view.displayPriority = .required
                view.glyphText = "\(stopAnnotation.stop.order)"
                switch stopAnnotation.stop.kind {
                case .departure, .returnHome:
                    view.markerTintColor = .systemIndigo
                case .arrival:
                    view.markerTintColor = .systemBlue
                case .internalStop:
                    view.markerTintColor = .systemOrange
                }
                return view
            }

            if let placeAnnotation = annotation as? PlacePinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: PlacePricePinView.reuseID,
                    for: annotation
                ) as? PlacePricePinView
                view?.configure(with: placeAnnotation.pin)
                return view
            }

            return nil
        }
    }
}

// MARK: - Annotations

private final class RouteStopAnnotation: NSObject, MKAnnotation {
    let stop: TourRouteStop
    dynamic var coordinate: CLLocationCoordinate2D { stop.coordinate }
    var title: String? { "\(stop.order). \(stop.city)" }
    var subtitle: String? { "\(stop.kind.rawValue) · \(stop.country)" }

    init(stop: TourRouteStop) {
        self.stop = stop
    }
}

private final class PlacePinAnnotation: NSObject, MKAnnotation {
    let pin: TourPlacePin
    dynamic var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.name }
    var subtitle: String? { "Day \(pin.dayNumber) · \(pin.category) · \(pin.priceLabel)" }

    init(pin: TourPlacePin) {
        self.pin = pin
    }
}

/// Price-tag pin: rounded label showing the ticket price above a small dot.
private final class PlacePricePinView: MKAnnotationView {
    static let reuseID = "tourPlacePricePin"

    private let pill = UIView()
    private let label = UILabel()
    private let dot = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        backgroundColor = .clear
        collisionMode = .circle

        pill.layer.cornerRadius = 9
        pill.layer.borderWidth = 1
        pill.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.25
        pill.layer.shadowRadius = 2
        pill.layer.shadowOffset = CGSize(width: 0, height: 1)

        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center

        dot.backgroundColor = .white
        dot.layer.cornerRadius = 3
        dot.layer.borderWidth = 1.5

        addSubview(pill)
        pill.addSubview(label)
        addSubview(dot)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with pin: TourPlacePin) {
        let isFree = (pin.ticketPriceUSD ?? 0) <= 0
        let tint: UIColor = isFree ? .systemGreen : .systemTeal
        pill.backgroundColor = tint
        dot.layer.borderColor = tint.cgColor
        label.text = pin.priceLabel

        let textWidth = label.text?.size(withAttributes: [.font: label.font as Any]).width ?? 24
        let pillWidth = max(30, ceil(textWidth) + 14)
        let pillHeight: CGFloat = 18
        let dotSize: CGFloat = 6
        let spacing: CGFloat = 3

        bounds = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight + spacing + dotSize)
        pill.frame = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        label.frame = pill.bounds
        dot.frame = CGRect(
            x: (pillWidth - dotSize) / 2,
            y: pillHeight + spacing,
            width: dotSize,
            height: dotSize
        )
        centerOffset = CGPoint(x: 0, y: -bounds.height / 2)
        displayPriority = isFree ? .defaultLow : .defaultHigh
    }
}
