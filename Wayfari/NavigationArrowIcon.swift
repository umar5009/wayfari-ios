import UIKit

enum NavigationArrowIcon {
    static func make(size: CGFloat = 36) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let cg = context.cgContext

            // Outer circle — Google Maps-style navigation puck
            cg.setFillColor(UIColor.systemBlue.cgColor)
            cg.fillEllipse(in: rect.insetBy(dx: 1, dy: 1))

            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))

            // Forward-pointing chevron arrow
            let arrow = UIBezierPath()
            let midX = rect.midX
            let topY = rect.minY + size * 0.22
            let bottomY = rect.maxY - size * 0.24
            let halfW = size * 0.14

            arrow.move(to: CGPoint(x: midX, y: topY))
            arrow.addLine(to: CGPoint(x: midX + halfW, y: bottomY - size * 0.08))
            arrow.addLine(to: CGPoint(x: midX + halfW * 0.45, y: bottomY - size * 0.08))
            arrow.addLine(to: CGPoint(x: midX + halfW * 0.45, y: bottomY))
            arrow.addLine(to: CGPoint(x: midX - halfW * 0.45, y: bottomY))
            arrow.addLine(to: CGPoint(x: midX - halfW * 0.45, y: bottomY - size * 0.08))
            arrow.addLine(to: CGPoint(x: midX - halfW, y: bottomY - size * 0.08))
            arrow.close()

            UIColor.white.setFill()
            arrow.fill()
        }
    }
}
