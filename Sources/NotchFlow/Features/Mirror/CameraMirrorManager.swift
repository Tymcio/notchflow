@preconcurrency import AVFoundation
import Foundation

/// Why the Mirror module shows no preview.
enum CameraMirrorIssue: Error, Equatable, Sendable {
    case permissionDenied
    /// No built-in, external or Continuity camera is connected (e.g. a Mac mini without a webcam).
    case noCameraFound
    /// A camera exists but the session could not use it (e.g. it is busy or was just unplugged).
    case startFailed
}

/// Camera preview for the Mirror module: the built-in front camera when there is one,
/// otherwise an external webcam or a Continuity Camera.
///
/// `AVCaptureSession` configuration, `startRunning()` and `stopRunning()` block for hundreds
/// of milliseconds while the camera powers up or down, so they run on a private session
/// queue; the main actor only publishes the result.
@MainActor
@Observable
final class CameraMirrorManager {
    private(set) var isActive = false
    private(set) var issue: CameraMirrorIssue?
    private(set) var previewFrame: CGImage?

    var permissionDenied: Bool { issue == .permissionDenied }

    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sampleBufferDelegate: CameraPreviewSampleBufferDelegate?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var stopTask: Task<Void, Never>?
    private var lastFrameDeliveredAt: ContinuousClock.Instant?
    private var isStarting = false
    /// The preview was reopened while a start that a stop had already cancelled was still
    /// powering up the camera; start again once it has finished.
    private var startRequestedDuringStart = false
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
        guard !isActive else { return }
        guard !isStarting else {
            // Only matters if a stop cancels the start in flight; see `runStart`.
            startRequestedDuringStart = true
            return
        }

        isStarting = true
        startRequestedDuringStart = false
        generation += 1
        let startGeneration = generation
        await runStart(generation: startGeneration)
        isStarting = false

        // Stopped while starting, then reopened before the camera finished powering up.
        if startGeneration != generation, startRequestedDuringStart {
            startRequestedDuringStart = false
            await startPreview()
        }
    }

    private func runStart(generation startGeneration: Int) async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                issue = .permissionDenied
                return
            }
        default:
            issue = .permissionDenied
            return
        }
        guard startGeneration == generation else { return }

        let delegate = CameraPreviewSampleBufferDelegate { [weak self] image in
            DispatchQueue.main.async { [weak self] in
                self?.deliverFrame(image, generation: startGeneration)
            }
        }
        let outputQueue = outputQueue
        let result: Result<ConfiguredCapture, CameraMirrorIssue> = await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: Self.makeRunningSession(delegate: delegate, outputQueue: outputQueue))
            }
        }

        let configured: ConfiguredCapture
        switch result {
        case .success(let capture):
            configured = capture
        case .failure(let failure):
            if startGeneration == generation {
                issue = failure
            }
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
        issue = nil
        startRequestedDuringStart = false
        configureRotation(for: configured.camera)
        scheduleAutoStop()
    }

    func stopPreview() {
        generation += 1
        startRequestedDuringStart = false
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
    ) -> Result<ConfiguredCapture, CameraMirrorIssue> {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium

        guard let camera = preferredCamera() else {
            return .failure(.noCameraFound)
        }
        guard let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            return .failure(.startFailed)
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
        guard captureSession.canAddOutput(output) else { return .failure(.startFailed) }
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
        return .success(ConfiguredCapture(session: captureSession, camera: camera, output: output))
    }

    /// Video cameras the Mirror can use: built-in, external webcams and Continuity Camera.
    private nonisolated static let cameraDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .external,
        .continuityCamera,
    ]

    /// The built-in front camera when present; Mac mini / Studio / Pro have none, so fall back
    /// to an external webcam, then a Continuity Camera. Runs on the session queue.
    private nonisolated static func preferredCamera() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: cameraDeviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices.filter { $0.isConnected && !$0.isSuspended }
        let kinds = devices.map { CameraKind(deviceType: $0.deviceType, position: $0.position) }
        return preferredCameraIndex(among: kinds).map { devices[$0] }
    }

    /// What camera selection needs to know about a device, so the ranking is testable.
    struct CameraKind: Equatable, Sendable {
        let deviceType: AVCaptureDevice.DeviceType
        let position: AVCaptureDevice.Position
    }

    /// Index of the camera to mirror: built-in front, other built-in, external, Continuity.
    nonisolated static func preferredCameraIndex(among cameras: [CameraKind]) -> Int? {
        func rank(_ camera: CameraKind) -> Int {
            switch camera.deviceType {
            case .builtInWideAngleCamera:
                return camera.position == .front ? 0 : 1
            case .external:
                return 2
            case .continuityCamera:
                return 3
            default:
                return 4
            }
        }
        return cameras.indices.min { rank(cameras[$0]) < rank(cameras[$1]) }
    }

    private func deliverFrame(_ image: CGImage, generation frameGeneration: Int) {
        // Frames already queued when the preview stopped (or restarted) must not reappear.
        guard isActive, frameGeneration == generation else { return }
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
