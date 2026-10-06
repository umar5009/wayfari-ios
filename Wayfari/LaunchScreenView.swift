import SwiftUI

// MARK: - Launch screen

struct LaunchScreenView: View {
    @Binding var isActive: Bool

    @State private var globeScale: CGFloat = 0.15
    @State private var globeOpacity: Double = 0
    @State private var orbitProgress: CGFloat = 0
    @State private var planeScale: CGFloat = 0
    @State private var trailOpacity: Double = 0
    @State private var logoOpacity: Double = 0
    @State private var logoOffset: CGFloat = 24
    @State private var backgroundPulse: CGFloat = 1

    private let orbitDuration: Double = 2.4
    private let totalDuration: Double = 3.6

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let orbitRadius = size * 0.28

            ZStack {
                background

                // Soft radial glow behind globe
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "007AFF").opacity(0.35),
                                Color(hex: "001A33").opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: orbitRadius * 1.6
                        )
                    )
                    .frame(width: orbitRadius * 3.2, height: orbitRadius * 3.2)
                    .scaleEffect(backgroundPulse)

                VStack(spacing: 28) {
                    ZStack {
                        orbitRing(radius: orbitRadius)

                        globe(size: orbitRadius * 1.35)
                            .scaleEffect(globeScale)
                            .opacity(globeOpacity)

                        flightTrail(radius: orbitRadius, progress: orbitProgress)
                            .opacity(trailOpacity)

                        airplane(radius: orbitRadius, progress: orbitProgress)
                            .scaleEffect(planeScale)
                    }
                    .frame(width: orbitRadius * 2.8, height: orbitRadius * 2.8)

                    VStack(spacing: 10) {
                        AppLogoMark(size: 56)
                        Text("Wayfari")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Explore the world")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .opacity(logoOpacity)
                    .offset(y: logoOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear(perform: runAnimation)
    }

    // MARK: - Layers

    private var background: some View {
        LinearGradient(
            colors: [
                Color(hex: "001A33"),
                Color(hex: "003D7A"),
                Color(hex: "007AFF").opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func orbitRing(radius: CGFloat) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        .white.opacity(0.05),
                        .white.opacity(0.35),
                        .white.opacity(0.05)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 8])
            )
            .frame(width: radius * 2, height: radius * 2)
            .opacity(trailOpacity)
    }

    private func globe(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "1B8FE8"), Color(hex: "0A5FA8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1.5)

            // Stylized continents
            GlobeContinentsShape()
                .fill(Color(hex: "2ECC71").opacity(0.85))
                .padding(size * 0.22)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .padding(size * 0.08)
                .blur(radius: 2)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: "007AFF").opacity(0.45), radius: 18, y: 8)
    }

    private func flightTrail(radius: CGFloat, progress: CGFloat) -> some View {
        let trailProgress = max(0, (progress - 0.12) / 0.88)

        return Circle()
            .trim(from: 0, to: trailProgress)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.7), .white.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
    }

    private func airplane(radius: CGFloat, progress: CGFloat) -> some View {
        AirplaneOrbitView(progress: progress, radius: radius)
    }

    // MARK: - Animation

    private func runAnimation() {
        withAnimation(.easeOut(duration: 0.55)) {
            globeScale = 1
            globeOpacity = 1
            backgroundPulse = 1.08
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(0.35)) {
            planeScale = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeInOut(duration: 0.35)) {
                trailOpacity = 1
            }
            withAnimation(.easeInOut(duration: orbitDuration)) {
                orbitProgress = 1
            }
        }

        withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(1.15)) {
            logoOpacity = 1
            logoOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            withAnimation(.easeInOut(duration: 0.45)) {
                isActive = false
            }
        }
    }
}

// MARK: - Airplane orbit

private struct AirplaneOrbitView: View, Animatable {
    var progress: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let departureEnd: CGFloat = 0.12
        let departure = min(progress / departureEnd, 1)
        let orbitFraction = max(0, (progress - departureEnd) / (1 - departureEnd))
        let angleDegrees = -90.0 + Double(orbitFraction) * 360.0
        let radians = angleDegrees * .pi / 180
        let currentRadius = radius * departure
        let x = cos(radians) * currentRadius
        let y = sin(radians) * currentRadius
        let heading = progress < 0.01 ? 45.0 : angleDegrees + 90.0

        Image(systemName: "airplane")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .rotationEffect(.degrees(heading))
            .offset(x: x, y: y)
    }
}

// MARK: - App logo mark

struct AppLogoMark: View {
    var size: CGFloat = 40

    var body: some View {
        let corner = size * 0.22
        let globeSize = size * 0.42

        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "007AFF"), Color(hex: "0056CC")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: "007AFF").opacity(0.45), radius: size * 0.12, y: size * 0.06)

            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: size * 0.028, lineCap: .round)
                )
                .frame(width: globeSize * 1.35, height: globeSize * 1.35)
                .rotationEffect(.degrees(-118))

            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.95), Color(hex: "D6ECFF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: globeSize, height: globeSize)
                .overlay {
                    GlobeContinentsShape()
                        .fill(Color(hex: "007AFF"))
                        .frame(width: globeSize * 0.62, height: globeSize * 0.62)
                }

            Image(systemName: "airplane")
                .font(.system(size: size * 0.11, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(32))
                .offset(x: globeSize * 0.52, y: -globeSize * 0.42)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Globe continents

private struct GlobeContinentsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.28, y: h * 0.34))
        path.addCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.28),
            control1: CGPoint(x: w * 0.34, y: h * 0.18),
            control2: CGPoint(x: w * 0.46, y: h * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.42),
            control1: CGPoint(x: w * 0.6, y: h * 0.36),
            control2: CGPoint(x: w * 0.68, y: h * 0.36)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.58, y: h * 0.62),
            control1: CGPoint(x: w * 0.76, y: h * 0.52),
            control2: CGPoint(x: w * 0.66, y: h * 0.6)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.3, y: h * 0.58),
            control1: CGPoint(x: w * 0.48, y: h * 0.66),
            control2: CGPoint(x: w * 0.38, y: h * 0.64)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.28, y: h * 0.34),
            control1: CGPoint(x: w * 0.2, y: h * 0.5),
            control2: CGPoint(x: w * 0.2, y: h * 0.4)
        )

        path.move(to: CGPoint(x: w * 0.18, y: h * 0.72))
        path.addCurve(
            to: CGPoint(x: w * 0.42, y: h * 0.76),
            control1: CGPoint(x: w * 0.24, y: h * 0.66),
            control2: CGPoint(x: w * 0.34, y: h * 0.68)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.22, y: h * 0.84),
            control1: CGPoint(x: w * 0.5, y: h * 0.86),
            control2: CGPoint(x: w * 0.3, y: h * 0.9)
        )
        path.closeSubpath()

        return path
    }
}

#Preview {
    LaunchScreenView(isActive: .constant(true))
}
