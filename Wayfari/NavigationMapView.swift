import SwiftUI
import MapKit

struct NavigationMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let pins: [MapPin]
    let routePolyline: MKPolyline?
    let destination: CLLocationCoordinate2D?
    let vehicleCoordinate: CLLocationCoordinate2D?
    let vehicleHeading: CLLocationDirection
    let showsUserLocation: Bool
    let isNavigating: Bool
    let onHotelTap: (Hotel) -> Void
    let onSpotTap: (SightSpot) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.showsCompass = true
        mapView.isRotateEnabled = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if isNavigating {
            mapView.setUserTrackingMode(.none, animated: true)
            let center = region.center
            if context.coordinator.lastCenter.latitude != center.latitude ||
                context.coordinator.lastCenter.longitude != center.longitude {
                mapView.setCenter(center, animated: true)
                context.coordinator.lastCenter = center
            }
        } else {
            mapView.setUserTrackingMode(.none, animated: false)
            if !context.coordinator.didFitRoute {
                mapView.setRegion(region, animated: true)
            }
        }

        context.coordinator.syncAnnotations(on: mapView)
        context.coordinator.syncRoute(on: mapView)
        context.coordinator.syncVehicle(on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NavigationMapView
        var didFitRoute = false
        var lastCenter = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        private var currentRouteID: ObjectIdentifier?
        private var vehicleAnnotation: VehicleAnnotation?

        init(_ parent: NavigationMapView) {
            self.parent = parent
        }

        func syncAnnotations(on mapView: MKMapView) {
            let nonVehicle = mapView.annotations.filter { !($0 is MKUserLocation) && !($0 is VehicleAnnotation) }
            mapView.removeAnnotations(nonVehicle)

            for pin in parent.pins {
                mapView.addAnnotation(PinAnnotation(pin: pin))
            }
            if let destination = parent.destination {
                mapView.addAnnotation(DestinationAnnotation(coordinate: destination))
            }
        }

        func syncRoute(on mapView: MKMapView) {
            guard let polyline = parent.routePolyline else {
                mapView.removeOverlays(mapView.overlays)
                currentRouteID = nil
                didFitRoute = false
                return
            }

            let routeID = ObjectIdentifier(polyline)
            if currentRouteID != routeID {
                mapView.removeOverlays(mapView.overlays)
                mapView.addOverlay(polyline)
                currentRouteID = routeID
                didFitRoute = false
            }

            if !didFitRoute || parent.isNavigating {
                let padding = UIEdgeInsets(top: 160, left: 40, bottom: parent.isNavigating ? 120 : 260, right: 40)
                mapView.setVisibleMapRect(polyline.boundingMapRect, edgePadding: padding, animated: true)
                didFitRoute = true
            }
        }

        func syncVehicle(on mapView: MKMapView) {
            guard parent.isNavigating, let coordinate = parent.vehicleCoordinate else {
                if let vehicleAnnotation {
                    mapView.removeAnnotation(vehicleAnnotation)
                    self.vehicleAnnotation = nil
                }
                return
            }

            if vehicleAnnotation == nil {
                let annotation = VehicleAnnotation(coordinate: coordinate, heading: parent.vehicleHeading)
                vehicleAnnotation = annotation
                mapView.addAnnotation(annotation)
            } else {
                vehicleAnnotation?.coordinate = coordinate
                vehicleAnnotation?.heading = parent.vehicleHeading
                if let view = mapView.view(for: vehicleAnnotation!) {
                    updateVehicleView(view, heading: parent.vehicleHeading)
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(Theme.accent)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let vehicle = annotation as? VehicleAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "vehicle") as? VehicleAnnotationView
                    ?? VehicleAnnotationView(annotation: annotation, reuseIdentifier: "vehicle")
                view.annotation = vehicle
                updateVehicleView(view, heading: vehicle.heading)
                return view
            }

            if annotation is DestinationAnnotation {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "destination")
                view.markerTintColor = .systemPurple
                view.glyphImage = UIImage(systemName: "flag.fill")
                return view
            }

            guard let pinAnnotation = annotation as? PinAnnotation else { return nil }

            switch pinAnnotation.pin.kind {
            case .hotel(let hotel):
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "hotel") as? HotelAnnotationView
                    ?? HotelAnnotationView(annotation: annotation, reuseIdentifier: "hotel")
                view.annotation = annotation
                view.configure(price: hotel.priceLabel)
                return view

            case .spot:
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "spot")
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "star.fill")
                return view
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pinAnnotation = view.annotation as? PinAnnotation else { return }
            mapView.deselectAnnotation(view.annotation, animated: true)

            switch pinAnnotation.pin.kind {
            case .hotel(let hotel):
                parent.onHotelTap(hotel)
            case .spot(let spot):
                parent.onSpotTap(spot)
            }
        }

        private func updateVehicleView(_ view: MKAnnotationView, heading: CLLocationDirection) {
            guard let vehicleView = view as? VehicleAnnotationView else { return }
            vehicleView.setHeading(heading)
        }
    }
}

private final class VehicleAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    dynamic var heading: CLLocationDirection

    init(coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        self.coordinate = coordinate
        self.heading = heading
    }
}

private final class VehicleAnnotationView: MKAnnotationView {
    private let iconView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        centerOffset = CGPoint(x: 0, y: 0)
        canShowCallout = false

        iconView.image = NavigationArrowIcon.make(size: 38)
        iconView.contentMode = .scaleAspectFit
        iconView.frame = bounds
        addSubview(iconView)

        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHeading(_ heading: CLLocationDirection) {
        let radians = CGFloat(heading * .pi / 180)
        iconView.transform = CGAffineTransform(rotationAngle: radians)
    }
}

private final class DestinationAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

private final class PinAnnotation: NSObject, MKAnnotation {
    let pin: MapPin

    var coordinate: CLLocationCoordinate2D { pin.coordinate }

    var title: String? {
        switch pin.kind {
        case .hotel(let hotel): return hotel.name
        case .spot(let spot): return spot.name
        }
    }

    init(pin: MapPin) {
        self.pin = pin
    }
}

private final class HotelAnnotationView: MKAnnotationView {
    private let priceLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 72, height: 34)
        centerOffset = CGPoint(x: 0, y: -17)
        canShowCallout = false

        priceLabel.font = .systemFont(ofSize: 12, weight: .bold)
        priceLabel.textAlignment = .center
        priceLabel.textColor = .label
        priceLabel.backgroundColor = .systemBackground
        priceLabel.layer.cornerRadius = 12
        priceLabel.layer.masksToBounds = true
        priceLabel.layer.borderColor = UIColor.black.withAlphaComponent(0.08).cgColor
        priceLabel.layer.borderWidth = 1
        addSubview(priceLabel)
    }

    func configure(price: String) {
        priceLabel.text = "  \(price)  "
        priceLabel.sizeToFit()
        priceLabel.frame = CGRect(x: 0, y: 0, width: max(priceLabel.frame.width, 52), height: 26)
        frame = priceLabel.frame
    }
}
