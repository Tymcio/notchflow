import AVFoundation
import Foundation

@MainActor
@Observable
final class CameraMirrorManager {
    private(set) var isActive = false
    private(set) var permissionDenied = false
    private(set) var previewFrame: CGImage?

    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sampleBufferDelegate: CameraPreviewSampleBufferDelegate?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var stopTask: Task<Void, Never>?
    private var lastFrameDeliveredAt: ContinuousClock.Instant?

    private let outputQueue = DispatchQueue(label: "eu.notchflow.camera-output", qos: .userInteractive)

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

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            permissionDenied = true
            return
        }

        try? camera.lockForConfiguration()
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        camera.unlockForConfiguration()

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard captureSession.canAddOutput(output) else {
            permissionDenied = true
            return
        }

        let delegate = CameraPreviewSampleBufferDelegate { [weak self] image in
            Task { @MainActor in
                self?.deliverFrame(image)
            }
        }
        output.setSampleBufferDelegate(delegate, queue: outputQueue)

        captureSession.addInput(input)
        captureSession.addOutput(output)

        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        captureSession.startRunning()

        session = captureSession
        device = camera
        videoOutput = output
        sampleBufferDelegate = delegate
        isActive = true
        permissionDenied = false
        configureRotation(for: camera)
        scheduleAutoStop()
    }

    func stopPreview() {
        stopTask?.cancel()
        rotationObservation = nil
        rotationCoordinator = nil
        session?.stopRunning()
        session = nil
        device = nil
        videoOutput = nil
        sampleBufferDelegate = nil
        previewFrame = nil
        lastFrameDeliveredAt = nil
        isActive = false
    }

    private func deliverFrame(_ image: CGImage) {
        let now = ContinuousClock.now
        if let lastFrameDeliveredAt, now - lastFrameDeliveredAt < .milliseconds(33) {
            return
        }
        lastFrameDeliveredAt = now
        previewFrame = image
    }

    private func configureRotation(for camera: AVCaptureDevice) {
        rotationObservation = nil
        rotationCoordinator = nil

        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationCoordinator = coordinator
        applyOutputRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] coordinator, _ in
            Task { @MainActor in
                self?.applyOutputRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }
    }

    private func applyOutputRotation(_ angle: CGFloat) {
        guard let connection = videoOutput?.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }
        connection.videoRotationAngle = angle
    }

    private func scheduleAutoStop() {
        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(for: .seconds(60))
            await MainActor.run { self.stopPreview() }
        }
    }
}
