import SwiftUI

/// Pozioma taśma czasu — ustawianie minut albo wizualny postęp odliczania.
struct FocusTimeRuler: View {
    @Binding var minutes: Int
    let accent: Color
    let isEnabled: Bool
    /// When set (active countdown), the ruler tracks remaining minutes instead of the draft binding.
    var progressMinutes: CGFloat? = nil

    private let minMinutes = 1
    private let maxMinutes = 90
    /// Pikseli na jedną minutę — mniejsza wartość = gęstsza, płynniejsza taśma.
    private let pointSpacing: CGFloat = 6

    @State private var dragAnchorMinute: CGFloat?
    @State private var liveCenterMinute: CGFloat?

    private var isTrackingProgress: Bool { progressMinutes != nil }

    private var displayCenter: CGFloat {
        if let progressMinutes {
            return min(CGFloat(maxMinutes), max(0, progressMinutes))
        }
        let center = liveCenterMinute ?? CGFloat(minutes)
        return min(CGFloat(maxMinutes), max(CGFloat(minMinutes), center))
    }

    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width * 0.5

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isTrackingProgress ? 0.06 : 0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                accent.opacity(isTrackingProgress ? 0.22 : 0.06),
                                lineWidth: 0.5
                            )
                    }

                rulerCanvas(midX: midX, width: geo.size.width)

                VStack(spacing: 0) {
                    Triangle()
                        .fill(accent)
                        .frame(width: 7, height: 4)
                    Rectangle()
                        .fill(accent.opacity(0.85))
                        .frame(width: 1.5, height: 20)
                }
                .position(x: midX, y: geo.size.height * 0.58)
                .shadow(color: accent.opacity(isTrackingProgress ? 0.55 : 0.4), radius: isTrackingProgress ? 5 : 3, y: 1)
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
            }
        }
        .frame(height: 44)
        .opacity(isEnabled || isTrackingProgress ? 1 : 0.45)
        .allowsHitTesting(isEnabled)
        .animation(.easeInOut(duration: 0.35), value: progressMinutes)
    }

    @ViewBuilder
    private func rulerCanvas(midX: CGFloat, width: CGFloat) -> some View {
        Canvas { context, size in
            let center = displayCenter
            let centerY = size.height * 0.58
            let floorMin = isTrackingProgress ? 0 : minMinutes
            let first = max(floorMin, Int(floor(center)) - 28)
            let last = min(maxMinutes, Int(ceil(center)) + 28)
            guard first <= last else { return }

            for minute in first...last {
                let offset = CGFloat(minute) - center
                let x = midX + offset * pointSpacing
                guard x >= -8, x <= width + 8 else { continue }

                let distance = abs(offset)
                let isCenter = distance < 0.35
                let isMajor = minute == 0 || minute.isMultiple(of: 5)
                let fade = max(0.1, 1 - distance * 0.04)

                let tickHeight: CGFloat = isCenter ? 15 : (isMajor ? 10 : 4)
                var path = Path()
                path.move(to: CGPoint(x: x, y: centerY - tickHeight / 2))
                path.addLine(to: CGPoint(x: x, y: centerY + tickHeight / 2))

                context.stroke(
                    path,
                    with: .color(
                        isCenter
                            ? accent.opacity(0.95)
                            : Color.white.opacity(Double(fade) * (isMajor ? 0.55 : 0.28))
                    ),
                    lineWidth: isCenter ? 2 : (isMajor ? 1 : 0.6)
                )

                if isMajor {
                    let label = Text("\(minute)")
                        .font(.system(size: isCenter ? 10 : 8, weight: isCenter ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isCenter ? accent : Color.white.opacity(Double(fade) * 0.65))
                    context.draw(context.resolve(label), at: CGPoint(x: x, y: 6), anchor: .center)
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: displayCenter)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard isEnabled else { return }
                if dragAnchorMinute == nil {
                    dragAnchorMinute = CGFloat(minutes)
                }
                let anchor = dragAnchorMinute ?? CGFloat(minutes)
                let live = anchor - value.translation.width / pointSpacing
                liveCenterMinute = min(CGFloat(maxMinutes), max(CGFloat(minMinutes), live))
                minutes = clamp(Int(live.rounded()))
            }
            .onEnded { _ in
                if let live = liveCenterMinute {
                    minutes = clamp(Int(live.rounded()))
                }
                dragAnchorMinute = nil
                liveCenterMinute = nil
            }
    }

    private func clamp(_ value: Int) -> Int {
        min(maxMinutes, max(minMinutes, value))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
