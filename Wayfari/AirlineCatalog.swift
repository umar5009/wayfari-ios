import Foundation

enum AirlineCatalog {
    static func logoURL(for code: String) -> URL {
        URL(string: "https://images.kiwi.com/airlines/64/\(code.uppercased()).png")!
    }

    static func fallbackLogoURL(for code: String) -> URL {
        URL(string: "https://pics.avs.io/128/128/\(code.uppercased()).png")!
    }

    static func airlineName(for code: String) -> String {
        switch code.uppercased() {
        case "EK": return "Emirates"
        case "PK": return "Pakistan Int'l Airlines"
        case "FZ": return "flydubai"
        case "G9": return "Air Arabia"
        case "QR": return "Qatar Airways"
        case "EY": return "Etihad Airways"
        case "TK": return "Turkish Airlines"
        case "SV": return "Saudi Arabian Airlines"
        case "GF": return "Gulf Air"
        case "WY": return "Oman Air"
        default: return code.uppercased()
        }
    }

    /// Opens the airline booking page with route + dates pre-filled where supported.
    static func bookingURL(
        airlineCode: String,
        origin: String,
        destination: String,
        departDate: Date,
        returnDate: Date?,
        isRoundTrip: Bool,
        adults: Int = 1
    ) -> URL {
        let from = origin.uppercased()
        let to = destination.uppercased()
        let dep = isoDate(departDate)
        let ret = returnDate.map(isoDate)

        switch airlineCode.uppercased() {
        case "TK":
            var url = "https://www.turkishairlines.com/en-int/flights/booking/?origin=\(from)&destination=\(to)&departureDate=\(dep)&adult=\(adults)"
            if isRoundTrip, let ret { url += "&returnDate=\(ret)" }
            return URL(string: url)!

        case "EK":
            return URL(string: "https://www.emirates.com/uk/english/book/flight-selection/?origin=\(from)&destination=\(to)&departureDate=\(dep)")!

        case "QR":
            var url = "https://www.qatarairways.com/en/book.html?origin=\(from)&destination=\(to)&departureDate=\(dep)&adults=\(adults)"
            if isRoundTrip, let ret { url += "&returnDate=\(ret)" }
            return URL(string: url)!

        case "FZ":
            return URL(string: "https://www.flydubai.com/en/book/flights?from=\(from)&to=\(to)&departure=\(dep)")!

        case "G9":
            return URL(string: "https://www.airarabia.com/en/book-flight?origin=\(from)&destination=\(to)&departureDate=\(dep)")!

        case "SV":
            return URL(string: "https://www.saudia.com/en/book-flight?origin=\(from)&destination=\(to)&departureDate=\(dep)")!

        case "EY":
            return URL(string: "https://www.etihad.com/en/book?origin=\(from)&destination=\(to)&departureDate=\(dep)")!

        case "PK":
            return URL(string: "https://www.piac.com.pk/booking?origin=\(from)&destination=\(to)&date=\(dep)")!

        case "GF":
            return URL(string: "https://www.gulfair.com/book?origin=\(from)&destination=\(to)&departure=\(dep)")!

        case "WY":
            return URL(string: "https://www.omanair.com/en/book?origin=\(from)&destination=\(to)&departureDate=\(dep)")!

        default:
            return URL(string: "https://www.google.com/travel/flights?q=Flights%20from%20\(from)%20to%20\(to)%20on%20\(dep)")!
        }
    }

    static func segmentBookingURL(
        segment: FlightSegment,
        departDate: Date,
        adults: Int
    ) -> URL {
        bookingURL(
            airlineCode: segment.iataCode,
            origin: segment.originCode,
            destination: segment.destinationCode,
            departDate: departDate,
            returnDate: nil,
            isRoundTrip: false,
            adults: adults
        )
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}
