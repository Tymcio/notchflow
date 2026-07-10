import AVFoundation
import SwiftUI

struct CameraMirrorView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            if appState.isPremium {
                if appState.cameraMirrorManager.isActive, let session = appState.cameraMirrorManager.captureSessionForPreview() {
                    CameraPreviewRepresentable(session: session)
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Label("Live", systemImage: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .padding(6)
                        }
                } else {
                    Button {
                        Task { await appState.cameraMirrorManager.startPreview() }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                                .foregroundStyle(IslandStyle.primaryText)
                            Text("Tap to enable camera")
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
                    Text("Camera access denied. Enable in System Settings.")
                        .font(.caption2)
                        .foregroundStyle(IslandStyle.secondaryText)
                }
            } else {
                Text("Camera Mirror is a Premium feature.")
                    .font(.caption)
                    .foregroundStyle(IslandStyle.secondaryText)
            }
        }
        .onDisappear {
            appState.cameraMirrorManager.stopPreview()
        }
    }
}

private struct CameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let layer = nsView.layer as? AVCaptureVideoPreviewLayer else { return }
        layer.session = session
        layer.frame = nsView.bounds
    }
}

import AppKit
