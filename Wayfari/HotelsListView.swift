import SwiftUI

struct HotelsListView: View {
    @State private var filter = "All Stars"
    @State private var hotels = SampleData.hotels
    private let filters = ["All Stars", "5 Star", "4 Star", "3 Star", "Price ↑"]

    private var visible: [Hotel] {
        switch filter {
        case "5 Star":  return hotels.filter { $0.stars == 5 }
        case "4 Star":  return hotels.filter { $0.stars == 4 }
        case "3 Star":  return hotels.filter { $0.stars == 3 }
        case "Price ↑": return hotels.sorted { $0.pricePerNight < $1.pricePerNight }
        default:        return hotels
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hotels in Dubai")
                        .font(.system(size: 24, weight: .bold))
                    Text("15–18 May  ·  2 Guests")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.sublabel)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { f in
                                ChipButton(title: f, isSelected: filter == f) { filter = f }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
                .padding(16)

                // Cards
                LazyVStack(spacing: 14) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, hotel in
                        HotelCard(hotel: hotel, colorIndex: idx) {
                            if let i = hotels.firstIndex(where: { $0.id == hotel.id }) {
                                hotels[i].isFavourite.toggle()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
    }
}

// MARK: - Hotel Card
struct HotelCard: View {
    let hotel: Hotel
    let colorIndex: Int
    let onFavourite: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Image area ────────────────────────────────────────
            ZStack(alignment: .topLeading) {
                HotelGradients.gradient(at: colorIndex)
                    .frame(height: 155)
                    .overlay(Text(hotel.emoji).font(.system(size: 52)))

                // Star badge top-left
                PillBadge(
                    text: "\(hotel.starsText)  \(hotel.stars) Star",
                    foreground: .white,
                    background: .black.opacity(0.50)
                )
                .padding(10)

                // Favourite top-right
                HStack {
                    Spacer()
                    Button(action: onFavourite) {
                        Image(systemName: hotel.isFavourite ? "heart.fill" : "heart")
                            .font(.system(size: 15))
                            .foregroundColor(.red)
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.92), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            }

            // ── Body ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                Text(hotel.name)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.bottom, 3)

                Label(hotel.neighbourhood, systemImage: "mappin")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.sublabel)
                    .padding(.bottom, 10)

                HStack(alignment: .center) {
                    StarRow(count: hotel.stars, size: 12)
                    Text(hotel.ratingText)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                        .padding(.leading, 4)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(hotel.priceLabel)
                            .font(.system(size: 20, weight: .bold))
                        Text("/night")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.sublabel)
                    }
                }
                .padding(.bottom, 10)

                // Amenity tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(hotel.amenities, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.sublabel)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }
}

#Preview { HotelsListView() }
