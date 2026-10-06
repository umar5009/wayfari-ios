import MapKit

enum RouteGeometry {
    static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords
    }

    static func makePolyline(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> MKPolyline {
        var coords = [start, end]
        return MKPolyline(coordinates: &coords, count: coords.count)
    }

    static func distance(_ polyline: MKPolyline) -> CLLocationDistance {
        let coords = coordinates(from: polyline)
        guard coords.count > 1 else { return 0 }

        var total: CLLocationDistance = 0
        for index in 1..<coords.count {
            let a = CLLocation(latitude: coords[index - 1].latitude, longitude: coords[index - 1].longitude)
            let b = CLLocation(latitude: coords[index].latitude, longitude: coords[index].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    static func closestPoint(on polyline: MKPolyline, to location: CLLocationCoordinate2D) -> (coordinate: CLLocationCoordinate2D, heading: CLLocationDirection, progress: Double) {
        let coords = coordinates(from: polyline)
        guard coords.count > 1 else {
            return (location, 0, 0)
        }

        let point = CLLocation(latitude: location.latitude, longitude: location.longitude)
        var bestCoord = coords[0]
        var bestHeading: CLLocationDirection = 0
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var traversed: CLLocationDistance = 0
        var bestTraversed: CLLocationDistance = 0

        for index in 1..<coords.count {
            let start = coords[index - 1]
            let end = coords[index]
            let projected = project(point: location, ontoSegmentFrom: start, to: end)
            let projectedLocation = CLLocation(latitude: projected.latitude, longitude: projected.longitude)
            let segmentDistance = projectedLocation.distance(from: point)

            if segmentDistance < bestDistance {
                bestDistance = segmentDistance
                bestCoord = projected
                bestHeading = bearing(from: start, to: end)
                bestTraversed = traversed + CLLocation(latitude: start.latitude, longitude: start.longitude)
                    .distance(from: projectedLocation)
            }

            traversed += CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        }

        let total = max(distance(polyline), 1)
        let progress = min(max(bestTraversed / total, 0), 1)
        return (bestCoord, bestHeading, progress)
    }

    static func coordinate(at progress: Double, on polyline: MKPolyline) -> (coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        let coords = coordinates(from: polyline)
        guard coords.count > 1 else {
            return (coords.first ?? kCLLocationCoordinate2DInvalid, 0)
        }

        let total = distance(polyline)
        let target = total * min(max(progress, 0), 1)
        var walked: CLLocationDistance = 0

        for index in 1..<coords.count {
            let start = coords[index - 1]
            let end = coords[index]
            let segment = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))

            if walked + segment >= target {
                let remaining = target - walked
                let fraction = segment > 0 ? remaining / segment : 0
                let lat = start.latitude + (end.latitude - start.latitude) * fraction
                let lon = start.longitude + (end.longitude - start.longitude) * fraction
                return (CLLocationCoordinate2D(latitude: lat, longitude: lon), bearing(from: start, to: end))
            }
            walked += segment
        }

        let last = coords[coords.count - 1]
        let previous = coords[coords.count - 2]
        return (last, bearing(from: previous, to: last))
    }

    static func remainingDistance(from location: CLLocationCoordinate2D, on polyline: MKPolyline) -> CLLocationDistance {
        let coords = coordinates(from: polyline)
        guard coords.count > 1 else { return 0 }

        let (_, _, progress) = closestPoint(on: polyline, to: location)
        return distance(polyline) * (1 - progress)
    }

    static func currentStepIndex(at location: CLLocationCoordinate2D, steps: [MKRoute.Step]) -> Int {
        guard !steps.isEmpty else { return 0 }

        let user = CLLocation(latitude: location.latitude, longitude: location.longitude)
        var bestIndex = 0
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude

        for (index, step) in steps.enumerated() {
            let snap = closestPoint(on: step.polyline, to: location)
            let d = user.distance(from: CLLocation(latitude: snap.coordinate.latitude, longitude: snap.coordinate.longitude))
            if d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }
        return bestIndex
    }

    static func guidance(at location: CLLocationCoordinate2D, steps: [MKRoute.Step]) -> TurnGuidance {
        guard steps.count > 1 else {
            return TurnGuidance(primary: "Head to destination", secondary: nil, icon: "arrow.up")
        }

        let currentIndex = currentStepIndex(at: location, steps: steps)
        let nextIndex = min(currentIndex + 1, steps.count - 1)
        let nextStep = steps[nextIndex]
        let distanceToManeuver = remainingDistance(from: location, on: steps[currentIndex].polyline)

        let instruction = nextStep.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = formatGuidance(instruction: instruction, distance: distanceToManeuver)
        let secondary = nextIndex + 1 < steps.count ? steps[nextIndex + 1].instructions : "Arrive at destination"
        let icon = maneuverIcon(for: instruction)

        return TurnGuidance(primary: primary, secondary: secondary, icon: icon)
    }

    static func formatGuidance(instruction: String, distance: CLLocationDistance) -> String {
        let lower = instruction.lowercased()
        let distText: String
        if distance < 25 {
            return instruction
        } else if distance >= 1000 {
            distText = String(format: "%.1f km", distance / 1000)
        } else {
            distText = "\(Int(round(distance / 50) * 50)) m"
        }

        if lower.contains("turn left") { return "Turn left in \(distText)" }
        if lower.contains("turn right") { return "Turn right in \(distText)" }
        if lower.contains("u-turn") { return "Make a U-turn in \(distText)" }
        if lower.contains("roundabout") { return "Enter roundabout in \(distText)" }
        if lower.contains("merge") { return "Merge in \(distText)" }
        if lower.contains("continue") || lower.contains("head") { return "Continue for \(distText)" }
        return "In \(distText), \(instruction)"
    }

    static func maneuverIcon(for instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("turn left") { return "arrow.turn.up.left" }
        if lower.contains("turn right") { return "arrow.turn.up.right" }
        if lower.contains("u-turn") { return "arrow.uturn.up" }
        if lower.contains("roundabout") { return "arrow.triangle.2.circlepath" }
        if lower.contains("merge") { return "arrow.merge" }
        return "arrow.up"
    }

    private static func project(
        point: CLLocationCoordinate2D,
        ontoSegmentFrom start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude

        if dx == 0 && dy == 0 { return start }

        let t = max(0, min(1, (
            (point.longitude - start.longitude) * dx +
            (point.latitude - start.latitude) * dy
        ) / (dx * dx + dy * dy)))

        return CLLocationCoordinate2D(
            latitude: start.latitude + t * dy,
            longitude: start.longitude + t * dx
        )
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

struct TurnGuidance {
    let primary: String
    let secondary: String?
    let icon: String
}
