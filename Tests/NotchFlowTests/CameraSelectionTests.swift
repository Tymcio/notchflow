import AVFoundation
import XCTest
@testable import NotchFlow

final class CameraSelectionTests: XCTestCase {
    private typealias Kind = CameraMirrorManager.CameraKind

    func testBuiltInFrontCameraWins() {
        let cameras = [
            Kind(deviceType: .continuityCamera, position: .unspecified),
            Kind(deviceType: .external, position: .unspecified),
            Kind(deviceType: .builtInWideAngleCamera, position: .front),
        ]
        XCTAssertEqual(CameraMirrorManager.preferredCameraIndex(among: cameras), 2)
    }

    /// Mac mini / Studio: no built-in camera, a USB webcam and an iPhone nearby.
    func testExternalWebcamBeforeContinuityCameraWithoutBuiltIn() {
        let cameras = [
            Kind(deviceType: .continuityCamera, position: .unspecified),
            Kind(deviceType: .external, position: .unspecified),
        ]
        XCTAssertEqual(CameraMirrorManager.preferredCameraIndex(among: cameras), 1)
    }

    func testContinuityCameraAloneIsUsed() {
        let cameras = [Kind(deviceType: .continuityCamera, position: .unspecified)]
        XCTAssertEqual(CameraMirrorManager.preferredCameraIndex(among: cameras), 0)
    }

    func testNoCameraGivesNoSelection() {
        XCTAssertNil(CameraMirrorManager.preferredCameraIndex(among: []))
    }
}
