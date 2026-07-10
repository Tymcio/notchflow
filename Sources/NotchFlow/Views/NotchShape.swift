import SwiftUI

struct NotchShape: Shape {
    let hasPhysicalNotch: Bool
    let isExpanded: Bool

    func path(in rect: CGRect) -> Path {
        if hasPhysicalNotch, !isExpanded {
            return idleNotchPath(in: rect)
        }
        return RoundedRectangle(cornerRadius: isExpanded ? 20 : 18, style: .continuous).path(in: rect)
    }

    private func idleNotchPath(in rect: CGRect) -> Path {
        var path = Path()
        let outerCorner: CGFloat = 12
        let earWidth = rect.width * 0.20
        let centerDip: CGFloat = 5

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + outerCorner))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + outerCorner, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + earWidth, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - earWidth, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY - centerDip)
        )
        path.addLine(to: CGPoint(x: rect.maxX - outerCorner, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + outerCorner),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
