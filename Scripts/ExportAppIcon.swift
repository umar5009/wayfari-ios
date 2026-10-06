#!/usr/bin/env swift
import SwiftUI
import AppKit

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

private struct AppIconView: View {
    var body: some View {
        let size: CGFloat = 1024
        let globeSize = size * 0.46

        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0, green: 0.48, blue: 1),
                    Color(red: 0, green: 0.34, blue: 0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
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
                            colors: [.white, Color(red: 0.84, green: 0.93, blue: 1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: globeSize, height: globeSize)
                    .overlay {
                        GlobeContinentsShape()
                            .fill(Color(red: 0, green: 0.48, blue: 1))
                            .frame(width: globeSize * 0.62, height: globeSize * 0.62)
                    }
                    .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.01)

                Image(systemName: "airplane")
                    .font(.system(size: size * 0.11, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(32))
                    .offset(x: globeSize * 0.52, y: -globeSize * 0.42)
                    .shadow(color: .black.opacity(0.2), radius: size * 0.008, y: size * 0.004)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
func exportIcon(to outputPath: String) throws {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = 1

    guard let image = renderer.nsImage else {
        throw NSError(domain: "ExportAppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render app icon."])
    }

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "ExportAppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG."])
    }

    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath)")
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

do {
    try MainActor.assumeIsolated {
        try exportIcon(to: outputPath)
    }
} catch {
    fputs("Failed to export icon: \(error)\n", stderr)
    exit(1)
}
