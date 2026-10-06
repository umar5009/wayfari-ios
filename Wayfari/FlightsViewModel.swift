import Foundation
import Combine

struct MultiCityLegResults: Identifiable {
    let id: UUID
    let leg: MultiCityLeg
    let flights: [Flight]
}

@MainActor
final class FlightsViewModel: ObservableObject {
    @Published var query: FlightSearchQuery
    @Published var flights: [Flight] = []
    @Published var multiCityResults: [MultiCityLegResults] = []
    @Published var sortFilter: FlightSortFilter = .all
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var searchFormExpanded = true

    init() {
        let from = AirportCatalog.all.first { $0.code == "LHE" } ?? AirportCatalog.all[0]
        let to = AirportCatalog.all.first { $0.code == "DXB" } ?? AirportCatalog.all[4]
        let cph = AirportCatalog.all.first { $0.code == "CPH" } ?? AirportCatalog.all[4]
        let fco = AirportCatalog.all.first { $0.code == "FCO" } ?? AirportCatalog.all[4]
        let depart = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let ret = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        let leg2Date = Calendar.current.date(byAdding: .day, value: 15, to: Date()) ?? Date()

        query = FlightSearchQuery(
            from: from,
            to: to,
            departDate: depart,
            returnDate: ret,
            tripType: .oneWay,
            passengers: FlightPassengers(),
            multiCityLegs: [
                MultiCityLeg(from: from, to: cph, date: depart),
                MultiCityLeg(from: fco, to: from, date: leg2Date),
            ]
        )
    }

    var visibleFlights: [Flight] {
        FlightScheduleService.sort(flights, by: sortFilter)
    }

    var collapsedSummaryTitle: String {
        if query.tripType == .multiCity {
            let codes = query.multiCityLegs.map { "\($0.from.code)–\($0.to.code)" }.joined(separator: ", ")
            return codes
        }
        return "\(query.from.code) – \(query.to.code)"
    }

    var collapsedSummaryDates: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        if query.tripType == .multiCity {
            let dates = query.multiCityLegs.map { fmt.string(from: $0.date) }
            return dates.joined(separator: " · ")
        }
        if query.tripType == .roundTrip {
            return "\(fmt.string(from: query.departDate)) – \(fmt.string(from: query.returnDate))"
        }
        return fmt.string(from: query.departDate)
    }

    var collapsedSummaryMeta: String {
        "\(query.tripType.rawValue) · \(query.passengers.total) traveler\(query.passengers.total > 1 ? "s" : "") · \(query.cabinClass)"
    }

    var headerSummary: String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d MMM"
        if query.tripType == .multiCity {
            return "\(query.multiCityLegs.count) flights · \(dateFmt.string(from: query.multiCityLegs.first?.date ?? Date())) · \(query.passengers.summary)"
        }
        var text = "\(query.from.code) → \(query.to.code) · \(dateFmt.string(from: query.departDate))"
        if query.tripType == .roundTrip {
            text += " – \(dateFmt.string(from: query.returnDate))"
        }
        text += " · \(query.passengers.summary)"
        return text
    }

    func swapAirports() {
        let temp = query.from
        query.from = query.to
        query.to = temp
    }

    func swapLeg(_ legID: UUID) {
        guard let i = query.multiCityLegs.firstIndex(where: { $0.id == legID }) else { return }
        let temp = query.multiCityLegs[i].from
        query.multiCityLegs[i].from = query.multiCityLegs[i].to
        query.multiCityLegs[i].to = temp
    }

    func addMultiCityLeg() {
        guard query.multiCityLegs.count < 5 else { return }
        let last = query.multiCityLegs.last
        let from = last?.to ?? query.from
        let to = query.from
        let date = Calendar.current.date(byAdding: .day, value: 3, to: last?.date ?? query.departDate) ?? Date()
        query.multiCityLegs.append(MultiCityLeg(from: from, to: to, date: date))
    }

    func removeMultiCityLeg(_ id: UUID) {
        guard query.multiCityLegs.count > 2 else { return }
        query.multiCityLegs.removeAll { $0.id == id }
    }

    func applyDeal(_ deal: FlightDeal) {
        if let dest = AirportCatalog.all.first(where: { $0.code == deal.airportCode }) {
            query.to = dest
            query.tripType = .roundTrip
            searchFormExpanded = true
        }
    }

    func search() {
        guard query.passengers.adults >= 1 else { return }

        if query.tripType == .multiCity {
            guard query.multiCityLegs.allSatisfy({ $0.from.code != $0.to.code }) else { return }
        } else {
            guard query.from.code != query.to.code else { return }
        }

        isSearching = true
        hasSearched = false
        searchFormExpanded = false

        Task {
            if query.tripType == .multiCity {
                let results = await FlightScheduleService.fetchMultiCity(for: query)
                multiCityResults = results.map {
                    MultiCityLegResults(id: $0.leg.id, leg: $0.leg, flights: FlightScheduleService.sort($0.flights, by: sortFilter))
                }
                flights = []
            } else {
                flights = await FlightScheduleService.fetchSchedules(for: query)
                multiCityResults = []
            }
            isSearching = false
            hasSearched = true
            sortFilter = .all
        }
    }

    func refreshSort() {
        if query.tripType == .multiCity {
            multiCityResults = multiCityResults.map {
                MultiCityLegResults(id: $0.id, leg: $0.leg, flights: FlightScheduleService.sort($0.flights, by: sortFilter))
            }
        }
    }
}
