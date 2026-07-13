import AVFoundation
import CoreImage
import Foundation

final class CameraPreviewSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @Sendable (CGImage) -> Void
    private let frameLock = NSLock()
    private var lastFrameProcessedAt: ContinuousClock.Instant?

    init(onFrame: @escaping @Sendable (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ContinuousClock.now
        frameLock.lock()
        if let lastFrameProcessedAt, now - lastFrameProcessedAt < .milliseconds(33) {
            frameLock.unlock()
            return
        }
        lastFrameProcessedAt = now
        frameLock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        onFrame(cgImage)
    }
}
