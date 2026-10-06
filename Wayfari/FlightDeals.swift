import SwiftUI

struct FlightDeal: Identifiable {
    let id = UUID()
    let destination: String
    let airportCode: String
    let duration: String
    let isNonStop: Bool
    let departLabel: String
    let returnLabel: String
    let priceUSD: Int
    let gradientStart: String
    let gradientEnd: String
    let emoji: String
}

enum FlightDealsCatalog {
    static let deals: [FlightDeal] = [
        FlightDeal(destination: "Kuwait City", airportCode: "KWI", duration: "1h 55m", isNonStop: true,
                   departLabel: "Sun 7/12", returnLabel: "Sun 7/19", priceUSD: 169,
                   gradientStart: "E8A838", gradientEnd: "1A3558", emoji: "🌅"),
        FlightDeal(destination: "Dubai", airportCode: "DXB", duration: "2h 45m", isNonStop: true,
                   departLabel: "Fri 8/7", returnLabel: "Sat 8/15", priceUSD: 189,
                   gradientStart: "F26B00", gradientEnd: "C01024", emoji: "🏙️"),
        FlightDeal(destination: "Istanbul", airportCode: "IST", duration: "3h 10m", isNonStop: false,
                   departLabel: "Mon 8/10", returnLabel: "Mon 8/17", priceUSD: 240,
                   gradientStart: "C8102E", gradientEnd: "5C0632", emoji: "🕌"),
        FlightDeal(destination: "Doha", airportCode: "DOH", duration: "2h 20m", isNonStop: true,
                   departLabel: "Wed 8/12", returnLabel: "Wed 8/19", priceUSD: 195,
                   gradientStart: "5C0632", gradientEnd: "2E5B8A", emoji: "🌃"),
        FlightDeal(destination: "Bangkok", airportCode: "BKK", duration: "4h 30m", isNonStop: false,
                   departLabel: "Thu 8/20", returnLabel: "Thu 8/27", priceUSD: 320,
                   gradientStart: "7AB87A", gradientEnd: "2E6E2E", emoji: "🛕"),
    ]

    static func deals(from originCode: String) -> [FlightDeal] {
        deals
    }
}

struct FlightDealCard: View {
    let deal: FlightDeal
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [Color(hex: deal.gradientStart), Color(hex: deal.gradientEnd)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(deal.emoji)
                        .font(.system(size: 48))
                        .padding(16)
                }
                .frame(width: 200, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(deal.destination)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.label)
                    Text("\(deal.duration), \(deal.isNonStop ? "non-stop" : "1 stop")")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                    Text("\(deal.departLabel) › \(deal.returnLabel)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.hint)
                    Text("from $\(deal.priceUSD)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.label)
                        .padding(.top, 2)
                }
                .padding(.top, 10)
            }
            .frame(width: 200)
        }
        .buttonStyle(.plain)
    }
}
