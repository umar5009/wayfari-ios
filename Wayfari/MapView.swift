import SwiftUI
import MapKit

// MARK: - Map annotation wrapper
struct MapPin: Identifiable {
    let id = UUID()
    enum Kind { case hotel(Hotel); case spot(SightSpot) }
    let kind: Kind
    var coordinate: CLLocationCoordinate2D {
        switch kind {
        case .hotel(let h): return h.coordinate
        case .spot(let s):  return s.coordinate
        }
    }
}

// MARK: - MapView
struct MapView: View {
    @EnvironmentObject private var exploreVM: ExploreViewModel
    @State private var selectedSpot: SightSpot?
    @State private var showSpotSheet = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationMapView(
                region: $exploreVM.mapRegion,
                pins: exploreVM.pins,
                routePolyline: exploreVM.isNavigating ? exploreVM.routePolyline : nil,
                destination: exploreVM.selectedPlace?.coordinate ?? exploreVM.selectedHotel?.coordinate,
                vehicleCoordinate: exploreVM.vehicleCoordinate,
                vehicleHeading: exploreVM.vehicleHeading,
                showsUserLocation: !exploreVM.isNavigating,
                isNavigating: exploreVM.isNavigating,
                onHotelTap: { hotel in
                    withAnimation(.spring(response: 0.28)) {
                        exploreVM.selectHotel(hotel)
                    }
                },
                onSpotTap: { spot in
                    selectedSpot = spot
                    showSpotSheet = true
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                MapSearchBar(
                    query: $exploreVM.searchQuery,
                    suggestions: exploreVM.suggestions,
                    isFocused: $searchFocused,
                    onQueryChange: exploreVM.onSearchQueryChanged,
                    onSelect: { place in
                        searchFocused = false
                        exploreVM.selectPlace(place)
                    },
                    onSubmit: exploreVM.submitSearch
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                if exploreVM.isNavigating, let guidance = exploreVM.turnGuidance {
                    TurnByTurnBanner(
                        guidance: guidance,
                        summary: exploreVM.routeSummary,
                        onStop: { exploreVM.stopNavigation() }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(spacing: 10) {
                if !exploreVM.isNavigating, let place = exploreVM.selectedPlace, exploreVM.selectedHotel == nil {
                    PlaceMapCard(
                        place: place,
                        contextSummary: exploreVM.placeContextSummary,
                        isCalculatingRoute: exploreVM.isCalculatingRoute,
                        isLoadingHotels: exploreVM.isLoadingHotels,
                        directionsFailed: exploreVM.directionsFailed,
                        onDirections: { exploreVM.startLiveNavigation() },
                        onOpenInMaps: {
                            if let coord = exploreVM.selectedPlace?.coordinate {
                                exploreVM.openInAppleMaps(destination: coord)
                            }
                        },
                        onDismiss: { exploreVM.clearSelection() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !exploreVM.isNavigating, let hotel = exploreVM.selectedHotel {
                    HotelMapCard(
                        hotel: hotel,
                        routeSummary: exploreVM.isCalculatingRoute ? "Calculating road route…" : "Tap for driving directions",
                        isNavigating: exploreVM.isCalculatingRoute,
                        canNavigate: !exploreVM.isCalculatingRoute,
                        onDirections: { exploreVM.startLiveNavigation() },
                        onDismiss: { exploreVM.clearSelection() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .sheet(isPresented: $showSpotSheet) {
            if let spot = selectedSpot {
                SpotDetailView(spot: spot)
                    .environmentObject(exploreVM)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: exploreVM.selectedPlace?.id)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: exploreVM.selectedHotel?.id)
    }
}

// MARK: - Search bar with autocomplete
struct MapSearchBar: View {
    @Binding var query: String
    let suggestions: [PlaceSearchResult]
    var isFocused: FocusState<Bool>.Binding
    let onQueryChange: (String) -> Void
    let onSelect: (PlaceSearchResult) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.hint)
                TextField("Search destination or place", text: $query)
                    .font(.system(size: 15))
                    .focused(isFocused)
                    .submitLabel(.search)
                    .onChange(of: query) { onQueryChange($0) }
                    .onSubmit { onSubmit() }
                    .onTapGesture { isFocused.wrappedValue = true }

                if !query.isEmpty {
                    Button {
                        query = ""
                        onQueryChange("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.hint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)

            if isFocused.wrappedValue, !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { place in
                        Button {
                            onSelect(place)
                        } label: {
                            HStack(spacing: 12) {
                                Text(place.emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(Theme.label)
                                    Text(place.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.sublabel)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let price = place.priceLabel {
                                    Text(price)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.accent)
                                }
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.hint)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)

                        if place.id != suggestions.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Route / navigation banners
struct RouteSummaryBar: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .foregroundColor(Theme.accent)
            Text(text)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TurnByTurnBanner: View {
    let guidance: TurnGuidance
    let summary: String?
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: guidance.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(guidance.primary)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let secondary = guidance.secondary {
                    Text(secondary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                } else if let summary {
                    Text(summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }

            Spacer(minLength: 8)

            Button("Stop", action: onStop)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 4)
    }
}

struct NavigationBanner: View {
    let status: String
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .foregroundColor(.white)
            Text(status)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button("Stop", action: onStop)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Place card (search result)
struct PlaceMapCard: View {
    let place: PlaceSearchResult
    let contextSummary: String?
    let isCalculatingRoute: Bool
    let isLoadingHotels: Bool
    let directionsFailed: Bool
    let onDirections: () -> Void
    let onOpenInMaps: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.15))
                    Text(place.emoji).font(.system(size: 30))
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Label(place.subtitle, systemImage: "mappin")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                    Text(place.category)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.accent)
                    if let price = place.priceLabel {
                        Text(price)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.accent)
                    }
                    if isLoadingHotels {
                        Text("Finding hotels & rentals…")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sublabel)
                    } else if let contextSummary {
                        Text(contextSummary)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sublabel)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(.systemGray3))
                }
            }

            Button(action: onDirections) {
                Label(
                    isCalculatingRoute ? "Calculating route…" : "Directions",
                    systemImage: isCalculatingRoute ? "hourglass" : "location.fill"
                )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .disabled(isCalculatingRoute || isLoadingHotels)

            if directionsFailed {
                Button(action: onOpenInMaps) {
                    Label("Open in Apple Maps", systemImage: "map")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 4)
    }
}

// MARK: - Hotel price pin (kept for previews)
struct HotelPin: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? .white : Theme.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isSelected ? Theme.accent : Theme.surface)
                        .shadow(color: .black.opacity(0.20), radius: 4, y: 2)
                )
            PinTail(color: isSelected ? Theme.accent : Theme.surface)
        }
    }
}

struct PinTail: View {
    let color: Color
    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: 10, height: 7)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

struct SpotPin: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.red).frame(width: 26, height: 26)
            Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.white)
        }
    }
}

// MARK: - Hotel card (map bottom sheet)
struct HotelMapCard: View {
    let hotel: Hotel
    let routeSummary: String?
    let isNavigating: Bool
    let canNavigate: Bool
    let onDirections: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(HotelGradients.gradient(at: SampleData.hotels.firstIndex(where: { $0.id == hotel.id }) ?? 0))
                    Text(hotel.emoji).font(.system(size: 30))
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 3) {
                    Text(hotel.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Label(hotel.neighbourhood, systemImage: "mappin")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                    StarRow(count: hotel.stars, size: 11)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(hotel.priceLabel)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.accent)
                        Text("/night")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sublabel)
                    }
                    if let routeSummary {
                        Text(routeSummary)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.sublabel)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(.systemGray3))
                }
            }

            HStack(spacing: 10) {
                Button(action: onDirections) {
                    Label(isNavigating ? "Navigating…" : "Directions", systemImage: "location.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background((canNavigate ? Theme.accent : Theme.accent.opacity(0.45)), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(isNavigating || !canNavigate)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 4)
    }
}

#Preview {
    MapView()
        .environmentObject(ExploreViewModel())
}
