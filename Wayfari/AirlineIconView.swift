import SwiftUI

// MARK: - Remote airline logo

struct AirlineIconView: View {
    let code: String
    var size: CGFloat = 32

    @State private var useFallback = false

    private var logoURL: URL {
        useFallback ? AirlineCatalog.fallbackLogoURL(for: code) : AirlineCatalog.logoURL(for: code)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(.systemBackground))

            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.12)
                case .failure:
                    AirlineIconPlaceholder(code: code, size: size)
                        .onAppear {
                            if !useFallback {
                                useFallback = true
                            }
                        }
                case .empty:
                    ProgressView()
                        .scaleEffect(0.6)
                @unknown default:
                    AirlineIconPlaceholder(code: code, size: size)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Fallback placeholder

private struct AirlineIconPlaceholder: View {
    let code: String
    let size: CGFloat

    private var brand: AirlineBrandStyle { AirlineBrandStyle.forCode(code) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(brand.background)
            Text(code.uppercased())
                .font(.system(size: size * 0.30, weight: .black))
                .foregroundColor(brand.foreground)
        }
    }
}

private struct AirlineBrandStyle {
    let background: Color
    let foreground: Color

    static func forCode(_ code: String) -> AirlineBrandStyle {
        switch code.uppercased() {
        case "TK": return AirlineBrandStyle(background: Color(hex: "C8102E"), foreground: .white)
        case "EK": return AirlineBrandStyle(background: Color(hex: "D71921"), foreground: .white)
        case "QR": return AirlineBrandStyle(background: Color(hex: "5C0632"), foreground: .white)
        case "EY": return AirlineBrandStyle(background: Color(hex: "BD8B13"), foreground: .white)
        case "PK": return AirlineBrandStyle(background: Color(hex: "003580"), foreground: .white)
        case "FZ": return AirlineBrandStyle(background: Color(hex: "F26B00"), foreground: .white)
        case "G9": return AirlineBrandStyle(background: Color(hex: "E10000"), foreground: .white)
        case "SV": return AirlineBrandStyle(background: Color(hex: "006747"), foreground: .white)
        case "GF": return AirlineBrandStyle(background: Color(hex: "A39063"), foreground: .white)
        case "WY": return AirlineBrandStyle(background: Color(hex: "004A8F"), foreground: .white)
        default:   return AirlineBrandStyle(background: Color(hex: "6B7280"), foreground: .white)
        }
    }
}

// MARK: - Overlapping row for multi-carrier itineraries

struct AirlineIconsRow: View {
    let codes: [String]
    var size: CGFloat = 28
    var overlap: CGFloat = 10

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(codes.enumerated()), id: \.offset) { index, code in
                AirlineIconView(code: code, size: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(Color(.systemBackground), lineWidth: 2)
                    )
                    .zIndex(Double(codes.count - index))
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            AirlineIconView(code: "TK", size: 40)
            AirlineIconView(code: "EK", size: 40)
            AirlineIconView(code: "G9", size: 40)
            AirlineIconView(code: "SV", size: 40)
        }
        AirlineIconsRow(codes: ["TK", "QR", "EK"], size: 36)
    }
    .padding()
}
