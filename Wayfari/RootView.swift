import SwiftUI

struct RootView: View {
    @StateObject private var exploreVM = ExploreViewModel()
    @State private var selectedTab: AppTab = .explore
    @State private var showChat = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // ── Content area ─────────────────────────────────
                ZStack {
                    ExploreView()
                        .environmentObject(exploreVM)
                        .opacity(selectedTab == .explore ? 1 : 0)
                        .allowsHitTesting(selectedTab == .explore)

                    RecentsView()
                        .opacity(selectedTab == .recents ? 1 : 0)
                        .allowsHitTesting(selectedTab == .recents)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ── AI trigger bar ───────────────────────────────
                AIChatTrigger(onTap: { showChat = true })

                // ── Tab bar ──────────────────────────────────────
                AppTabBar(selected: $selectedTab)
            }
            .ignoresSafeArea(edges: .bottom)

            // ── Full-screen AI chat ──────────────────────────────
            if showChat {
                AIChatView(isPresented: $showChat)
                    .transition(.move(edge: .bottom))
                    .zIndex(200)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: showChat)
    }
}

// MARK: - Tab enum
enum AppTab: String, CaseIterable {
    case explore = "Explore"
    case recents = "Recents"

    var icon: String {
        switch self {
        case .explore: return "map"
        case .recents: return "clock"
        }
    }
}

// MARK: - AI trigger bar
struct AIChatTrigger: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan with Wayfari AI")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.label)
                    Text("Voice or type — full tours, flights & hotels")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sublabel)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.hint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .overlay(Divider(), alignment: .top)
            .overlay(Divider(), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab bar
struct AppTabBar: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: { selected = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                            .foregroundColor(selected == tab ? Theme.accent : Theme.hint)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(selected == tab ? Theme.accent : Theme.hint)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
        .background(Theme.surface)
        .overlay(Divider(), alignment: .top)
    }
}

#Preview {
    RootView()
}
