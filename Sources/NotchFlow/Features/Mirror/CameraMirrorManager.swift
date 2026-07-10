import AVFoundation
import Foundation

@MainActor
@Observable
final class CameraMirrorManager {
    private(set) var isActive = false
    private(set) var permissionDenied = false

    private var session: AVCaptureSession?
    private var stopTask: Task<Void, Never>?

    func startPreview() async {
        guard !isActive else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                permissionDenied = true
                return
            }
        default:
            permissionDenied = true
            return
        }

        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            permissionDenied = true
            return
        }

        captureSession.addInput(input)
        captureSession.startRunning()
        session = captureSession
        isActive = true
        permissionDenied = false
        scheduleAutoStop()
    }

    func stopPreview() {
        stopTask?.cancel()
        session?.stopRunning()
        session = nil
        isActive = false
    }

    func captureSessionForPreview() -> AVCaptureSession? {
        session
    }

    private func scheduleAutoStop() {
        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(for: .seconds(60))
            await MainActor.run { self.stopPreview() }
        }
    }
}
