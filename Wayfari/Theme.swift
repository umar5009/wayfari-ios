import SwiftUI

// MARK: - App Theme
enum Theme {
    static let accent     = Color.blue
    static let background = Color(.systemGroupedBackground)
    static let surface    = Color(.systemBackground)
    static let secondary  = Color(.secondarySystemBackground)
    static let separator  = Color(.separator)
    static let label      = Color(.label)
    static let sublabel   = Color(.secondaryLabel)
    static let hint       = Color(.tertiaryLabel)
}

// MARK: - Gradient catalogue
struct HotelGradients {
    static let all: [[Color]] = [
        [Color(hex: "c89b6e"), Color(hex: "7a4a24")],
        [Color(hex: "5b8fb9"), Color(hex: "1e4878")],
        [Color(hex: "7ab87a"), Color(hex: "2e6e2e")],
        [Color(hex: "b87ab8"), Color(hex: "6e2e6e")],
        [Color(hex: "b88a7a"), Color(hex: "7a4a3a")],
    ]
    static func gradient(at index: Int) -> LinearGradient {
        let pair = all[index % all.count]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SpotGradients {
    static func gradient(start: String, end: String) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: start), Color(hex: end)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Color hex init
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Shared Components

/// Pill filter chip
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : Theme.sublabel)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Theme.label : Color.clear)
                )
                .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

/// Star row
struct StarRow: View {
    let count: Int
    let size: CGFloat

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(i < count ? .yellow : Theme.hint)
            }
        }
    }
}

/// Pill badge
struct PillBadge: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Airline colour lookup
func airlineColor(_ code: String) -> Color {
    switch code {
    case "PK": return Color(hex: "003580")
    case "EK": return Color(hex: "C01024")
    case "FZ": return Color(hex: "F26B00")
    case "G9": return Color(hex: "E10000")
        case "QR": return Color(hex: "5C0632")
        case "EY": return Color(hex: "BD8B13")
        case "TK": return Color(hex: "C8102E")
        case "SV": return Color(hex: "006747")
        case "GF": return Color(hex: "A39063")
        case "WY": return Color(hex: "004A8F")
        default:   return Color.gray
    }
}

// MARK: - Navigation bar logo
struct WayfariLogo: View {
    var body: some View {
        HStack(spacing: 8) {
            AppLogoMark(size: 30)
            Text("Way") + Text("fari").foregroundColor(Theme.accent)
        }
        .font(.system(size: 18, weight: .bold))
    }
}
