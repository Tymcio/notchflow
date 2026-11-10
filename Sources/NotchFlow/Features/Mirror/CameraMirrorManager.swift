@preconcurrency import AVFoundation
import Foundation

/// Front-camera preview for the Mirror module.
///
/// `AVCaptureSession` configuration, `startRunning()` and `stopRunning()` block for hundreds
/// of milliseconds while the camera powers up or down, so they run on a private session
/// queue; the main actor only publishes the result.
@MainActor
@Observable
final class CameraMirrorManager {
    private(set) var isActive = false
    private(set) var permissionDenied = false
    private(set) var previewFrame: CGImage?

    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sampleBufferDelegate: CameraPreviewSampleBufferDelegate?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var stopTask: Task<Void, Never>?
    private var lastFrameDeliveredAt: ContinuousClock.Instant?
    private var isStarting = false
    /// Bumped by every start/stop so a start that finishes after a stop is discarded.
    private var generation = 0

    private let outputQueue = DispatchQueue(label: "eu.notchflow.camera-output", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "eu.notchflow.camera-session", qos: .userInitiated)

    /// Capture objects created on the session queue. `@unchecked Sendable`: they are handed
    /// over once and afterwards only touched on the main actor or the session queue.
    private struct ConfiguredCapture: @unchecked Sendable {
        let session: AVCaptureSession
        let camera: AVCaptureDevice
        let output: AVCaptureVideoDataOutput
    }

    private struct SessionBox: @unchecked Sendable {
        let session: AVCaptureSession
    }

    func startPreview() async {
        guard !isActive, !isStarting else { return }

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

        isStarting = true
        defer { isStarting = false }
        generation += 1
        let startGeneration = generation

        let delegate = CameraPreviewSampleBufferDelegate { [weak self] image in
            DispatchQueue.main.async { [weak self] in
                self?.deliverFrame(image)
            }
        }
        let outputQueue = outputQueue
        let configured: ConfiguredCapture? = await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: Self.makeRunningSession(delegate: delegate, outputQueue: outputQueue))
            }
        }

        guard let configured else {
            permissionDenied = true
            return
        }
        // Stopped (or restarted) while the camera was powering up.
        guard startGeneration == generation else {
            stopRunning(configured.session)
            return
        }

        session = configured.session
        videoOutput = configured.output
        sampleBufferDelegate = delegate
        isActive = true
        permissionDenied = false
        configureRotation(for: configured.camera)
        scheduleAutoStop()
    }

    func stopPreview() {
        generation += 1
        stopTask?.cancel()
        stopTask = nil
        rotationObservation = nil
        rotationCoordinator = nil
        if let session {
            stopRunning(session)
        }
        session = nil
        videoOutput = nil
        sampleBufferDelegate = nil
        previewFrame = nil
        lastFrameDeliveredAt = nil
        isActive = false
    }

    private func stopRunning(_ session: AVCaptureSession) {
        let box = SessionBox(session: session)
        sessionQueue.async {
            box.session.stopRunning()
        }
    }

    /// Builds and starts the capture session. Runs on the session queue.
    private nonisolated static func makeRunningSession(
        delegate: CameraPreviewSampleBufferDelegate,
        outputQueue: DispatchQueue
    ) -> ConfiguredCapture? {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            return nil
        }

        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            camera.unlockForConfiguration()
        } catch {
            NotchFlowLog.camera.debug("Camera frame-rate lock failed: \(error.localizedDescription, privacy: .public)")
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        guard captureSession.canAddOutput(output) else { return nil }
        output.setSampleBufferDelegate(delegate, queue: outputQueue)

        captureSession.beginConfiguration()
        captureSession.addInput(input)
        captureSession.addOutput(output)
        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        captureSession.commitConfiguration()

        captureSession.startRunning()
        return ConfiguredCapture(session: captureSession, camera: camera, output: output)
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
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async { [weak self] in
                self?.applyOutputRotation(angle)
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
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.stopPreview()
        }
    }
}
