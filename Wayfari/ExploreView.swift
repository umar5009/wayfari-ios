import SwiftUI

// MARK: - Explore tabs
enum ExploreTab: String, CaseIterable {
    case map         = "Map"
    case flights     = "Flights"
    case hotels      = "Hotels"
    case sightseeing = "Sightseeing"
}

// MARK: - ExploreView
struct ExploreView: View {
    @EnvironmentObject private var exploreVM: ExploreViewModel
    @State private var activeTab: ExploreTab = .map

    var body: some View {
        VStack(spacing: 0) {
            TopNavBar(activeTab: $activeTab, onSearchTap: {
                activeTab = .map
            })

            ZStack {
                MapView()
                    .opacity(activeTab == .map ? 1 : 0)
                    .allowsHitTesting(activeTab == .map)

                FlightsListView()
                    .opacity(activeTab == .flights ? 1 : 0)
                    .allowsHitTesting(activeTab == .flights)

                HotelsListView()
                    .opacity(activeTab == .hotels ? 1 : 0)
                    .allowsHitTesting(activeTab == .hotels)

                SightSeeingListView()
                    .opacity(activeTab == .sightseeing ? 1 : 0)
                    .allowsHitTesting(activeTab == .sightseeing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: exploreVM.selectedPlace?.id) { _ in
            if exploreVM.selectedPlace != nil { activeTab = .map }
        }
        .onChange(of: exploreVM.isNavigating) { navigating in
            if navigating { activeTab = .map }
        }
    }
}

// MARK: - Top Navigation Bar
struct TopNavBar: View {
    @Binding var activeTab: ExploreTab
    var onSearchTap: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Logo row
            HStack {
                WayfariLogo()
                Spacer()
                HStack(spacing: 8) {
                    navButton("magnifyingglass", action: onSearchTap)
                    navButton("bell")
                    navButton("person.circle")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Segmented control
            HStack(spacing: 4) {
                ForEach(ExploreTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                    }) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: activeTab == tab ? .semibold : .medium))
                            .foregroundColor(activeTab == tab ? Theme.label : Theme.sublabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(activeTab == tab ? Theme.surface : Color.clear)
                                    .shadow(color: .black.opacity(activeTab == tab ? 0.10 : 0), radius: 2, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()
        }
        .background(.ultraThinMaterial)
    }

    private func navButton(_ icon: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Color(.systemGray5), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ExploreView()
        .environmentObject(ExploreViewModel())
}
