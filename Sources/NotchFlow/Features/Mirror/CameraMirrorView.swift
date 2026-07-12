import SwiftUI

struct CameraMirrorView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            if appState.isPremium {
                if appState.cameraMirrorManager.isActive {
                    cameraPreview
                } else {
                    Button {
                        AppController.panelController?.prepareForTyping()
                        Task { await appState.cameraMirrorManager.startPreview() }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                                .foregroundStyle(IslandStyle.primaryText)
                            Text("Dotknij, aby włączyć kamerę")
                                .font(.caption)
                                .foregroundStyle(IslandStyle.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                .foregroundStyle(IslandStyle.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if appState.cameraMirrorManager.permissionDenied {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Brak dostępu do kamery.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IslandStyle.primaryText)
                        Text("Włącz NotchFlow w Ustawienia systemowe → Prywatność i ochrona → Kamera.")
                            .font(.caption2)
                            .foregroundStyle(IslandStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Otwórz ustawienia kamery") {
                            SystemSettingsLink.openCameraPrivacy()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(IslandStyle.accentText)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                            .foregroundStyle(IslandStyle.tertiaryText)
                        VStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                                .foregroundStyle(IslandStyle.secondaryText)
                            Text("Premium")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(IslandStyle.tertiaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)

                    Text("Lustro kamery jest funkcją Premium.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IslandStyle.primaryText)
                    Text("Aktywuj licencję w Ustawienia → Licencja, a potem wróć tutaj.")
                        .font(.caption2)
                        .foregroundStyle(IslandStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Otwórz aktywację licencji") {
                        appState.openLicenseSettings()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: 220)
        .onDisappear {
            appState.cameraMirrorManager.stopPreview()
        }
    }

    @ViewBuilder
    private var cameraPreview: some View {
        ZStack {
            if let frame = appState.cameraMirrorManager.previewFrame {
                Image(decorative: frame, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Label("Na żywo", systemImage: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .padding(6)
        }
    }
}
