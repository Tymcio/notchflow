import SwiftUI

struct CalendarPreviewView: View {
    let event: CalendarEventPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next Meeting", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(event.title)
                .font(.caption)
                .lineLimit(1)
            Text(event.formattedCountdown)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let meetingURL = event.meetingURL {
                Link("Join", destination: meetingURL)
                    .font(.caption2)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
