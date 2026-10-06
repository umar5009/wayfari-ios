import SwiftUI

struct RecentsView: View {
    private let items    = SampleData.recents
    private let trending = [
        ("🇹🇷", "Istanbul",      "Turkey",         "From $420"),
        ("🇲🇾", "Kuala Lumpur",  "Malaysia",       "From $380"),
        ("🇬🇧", "London",         "United Kingdom", "From $780"),
        ("🇯🇵", "Tokyo",          "Japan",          "From $920"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recents")
                        .font(.system(size: 24, weight: .bold))
                    Text("Your recent searches & saved interests")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.sublabel)
                }
                .padding(16)

                // ── Recent list ───────────────────────────────────
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        RecentRow(item: item)
                        if idx < items.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
                .padding(.horizontal, 16)

                // ── Trending ──────────────────────────────────────
                Text("Trending Now")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(trending, id: \.1) { flag, city, country, price in
                            TrendingCard(flag: flag, city: city, country: country, price: price)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 24)
            }
        }
        .background(Theme.background)
    }
}

// MARK: - Recent row
struct RecentRow: View {
    let item: RecentItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                    .frame(width: 38, height: 38)
                Text(item.emoji).font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.sublabel)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.price)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text(item.timeAgo)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.hint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

// MARK: - Trending card
struct TrendingCard: View {
    let flag: String
    let city: String
    let country: String
    let price: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(flag).font(.system(size: 36))
            Text(city).font(.system(size: 15, weight: .semibold))
            Text(country).font(.system(size: 12)).foregroundColor(Theme.sublabel)
            Text(price).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.accent)
        }
        .padding(14)
        .frame(width: 145)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }
}

#Preview { RecentsView() }
