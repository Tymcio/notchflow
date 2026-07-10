import SwiftUI

struct MediaScrubberView: View {
    let position: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragFraction = 0.0

    private let trackHeight: CGFloat = 5
    private let hitHeight: CGFloat = 20

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let fraction = isDragging ? dragFraction : safeFraction
                let knobX = max(0, min(width, width * fraction))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: knobX, height: trackHeight)

                    Circle()
                        .fill(.white)
                        .frame(width: isDragging ? 14 : 11, height: isDragging ? 14 : 11)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: knobX - (isDragging ? 7 : 5.5))
                }
                .frame(height: hitHeight)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragFraction = max(0, min(1, value.location.x / width))
                        }
                        .onEnded { value in
                            let finalFraction = max(0, min(1, value.location.x / width))
                            dragFraction = finalFraction
                            onSeek(finalFraction * duration)
                            isDragging = false
                        }
                )
            }
            .frame(height: hitHeight)

            HStack {
                Text(formatTime(isDragging ? dragFraction * duration : position))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .monospacedDigit()
        }
    }

    private var safeFraction: Double {
        guard MediaPlaybackState.isUsableTiming(duration) else { return 0 }
        return max(0, min(1, position / duration))
    }

    private func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
