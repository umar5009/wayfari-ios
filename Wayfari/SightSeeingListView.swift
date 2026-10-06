import SwiftUI

// MARK: - Sightseeing list
struct SightSeeingListView: View {
    @EnvironmentObject private var exploreVM: ExploreViewModel
    private let spots = SampleData.spots
    @State private var selected: SightSpot?
    @State private var showDetail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CityBannerView()
                    .padding(16)

                LazyVStack(spacing: 12) {
                    ForEach(Array(spots.enumerated()), id: \.element.id) { idx, spot in
                        SiteCard(spot: spot, colorIndex: idx) {
                            selected   = spot
                            showDetail = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showDetail) {
            if let spot = selected {
                SpotDetailView(spot: spot)
                    .environmentObject(exploreVM)
            }
        }
    }
}

// MARK: - City banner
struct CityBannerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Dubai").font(.system(size: 26, weight: .bold)).foregroundColor(.white)
            Text("United Arab Emirates  ·  GMT+4")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.72))
                .padding(.top, 2)
            Text("A dazzling city of superlatives — home to the world's tallest building, largest mall, and most luxurious hotels, rising from the desert on the Persian Gulf.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(3)
                .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "1C3557"), Color(hex: "0A1F3A")],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}

// MARK: - Site row card
private let spotGradients: [([Color])] = [
    [Color(hex: "8B5E3C"), Color(hex: "5C3A20")],
    [Color(hex: "2E5B8A"), Color(hex: "1A3558")],
    [Color(hex: "5C3A8A"), Color(hex: "38205C")],
    [Color(hex: "2E8A5B"), Color(hex: "1A5C38")],
    [Color(hex: "8A2E2E"), Color(hex: "5C1A1A")],
]

struct SiteCard: View {
    let spot: SightSpot
    let colorIndex: Int
    let onTap: () -> Void

    private var grad: LinearGradient {
        let pair = spotGradients[colorIndex % spotGradients.count]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    grad.frame(height: 110)
                        .overlay(Text(spot.emoji).font(.system(size: 48)))

                    HStack {
                        PillBadge(
                            text: spot.category.uppercased(),
                            foreground: .white,
                            background: .black.opacity(0.50)
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(9)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.label)
                    Text(spot.about)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.sublabel)
                        .lineLimit(2)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }
}

// MARK: - Spot detail (full NavigationView sheet)
struct SpotDetailView: View {
    let spot: SightSpot
    @EnvironmentObject private var exploreVM: ExploreViewModel
    @Environment(\.dismiss) private var dismiss

    private var grad: LinearGradient {
        LinearGradient(
            colors: [Color(hex: spot.gradientStart), Color(hex: spot.gradientEnd)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Hero
                    ZStack {
                        grad.frame(maxWidth: .infinity).frame(height: 240)
                        Text(spot.emoji).font(.system(size: 80))
                    }

                    // Photo strip
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(spot.photoEmojis.enumerated()), id: \.offset) { _, em in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(grad).frame(width: 120, height: 82)
                                    Text(em).font(.system(size: 36))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 22) {

                        // Name + meta
                        VStack(alignment: .leading, spacing: 8) {
                            Text(spot.name).font(.system(size: 22, weight: .bold))
                            HStack(spacing: 14) {
                                Label(spot.neighbourhood, systemImage: "mappin")
                                Label(String(format: "%.1f  ·  %@ visits", spot.rating, spot.visitCount), systemImage: "star")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.sublabel)
                        }

                        // About
                        DetailSection(title: "About") {
                            Text(spot.about)
                                .font(.system(size: 15))
                                .foregroundColor(Color(.label).opacity(0.82))
                                .lineSpacing(4)
                        }

                        // Key facts
                        DetailSection(title: "Key Facts") {
                            HStack(spacing: 8) {
                                ForEach(spot.facts, id: \.label) { fact in
                                    FactTile(value: fact.value, label: fact.label)
                                }
                            }
                        }

                        // Travel tips
                        DetailSection(title: "Travel Tips") {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text(spot.tips)
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(.label).opacity(0.82))
                                    .lineSpacing(4)
                            }
                            .padding(12)
                            .background(Color.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        }

                        // CTA
                        Button {
                            dismiss()
                            if let place = SearchCatalog.allPlaces.first(where: { $0.id == spot.id }) {
                                exploreVM.selectPlace(place)
                            } else {
                                let place = PlaceSearchResult(
                                    id: spot.id,
                                    name: spot.name,
                                    subtitle: spot.neighbourhood,
                                    category: spot.category,
                                    emoji: spot.emoji,
                                    latitude: spot.latitude,
                                    longitude: spot.longitude,
                                    priceLabel: "From AED 50",
                                    searchKeywords: [spot.name.lowercased()]
                                )
                                exploreVM.selectPlace(place)
                            }
                            exploreVM.startLiveNavigation()
                        } label: {
                            Label("Get Directions", systemImage: "map")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 15))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}

// MARK: - Detail section wrapper
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .semibold))
            content
        }
    }
}

// MARK: - Fact tile
struct FactTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 17, weight: .bold))
            Text(label).font(.system(size: 11)).foregroundColor(Theme.sublabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview { SightSeeingListView() }
