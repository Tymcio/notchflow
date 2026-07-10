import SwiftUI

struct PomodoroView: View {
    let state: PomodoroState
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Pomodoro", systemImage: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(state.formattedTime)
                    .font(.title3.monospacedDigit())
                Spacer()
                Button(state.isRunning ? "Pause" : "Start", action: onToggle)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
