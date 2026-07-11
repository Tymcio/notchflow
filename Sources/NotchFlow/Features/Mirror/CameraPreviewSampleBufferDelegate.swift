import AVFoundation
import CoreImage

final class CameraPreviewSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @Sendable (CGImage) -> Void

    init(onFrame: @escaping @Sendable (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        onFrame(cgImage)
    }
}
