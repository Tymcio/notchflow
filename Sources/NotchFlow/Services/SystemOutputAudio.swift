import AudioToolbox
import CoreAudio
import Foundation

struct SystemOutputLevel: Equatable, Sendable {
    let volume: Double
    let isMuted: Bool
}

/// Reads the default output device mute / volume — used when timer alerts must fall back to
/// visuals, and by the volume HUD.
enum SystemOutputAudio {
    /// True when the Mac mute key is on or output volume is effectively zero.
    static var isSilent: Bool {
        guard let deviceID = defaultOutputDeviceID else { return false }
        if isMuted(deviceID) { return true }
        return volume(deviceID) < 0.01
    }

    /// Level of the output device, or `nil` when it has no volume control (some HDMI / USB
    /// outputs): the volume keys cannot change it, so there is nothing to show.
    static func outputLevel(of deviceID: AudioDeviceID) -> SystemOutputLevel? {
        guard let volume = controllableVolume(deviceID) else { return nil }
        return SystemOutputLevel(volume: Double(min(max(volume, 0), 1)), isMuted: isMuted(deviceID))
    }

    /// Volume and mute properties a level listener registers for (each one only if the device has it).
    static let levelPropertyAddresses: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
        (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyMute, 1),
        (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyVolumeScalar, 1),
        (kAudioDevicePropertyVolumeScalar, 2),
    ]

    static var defaultOutputDeviceID: AudioDeviceID? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func isMuted(_ deviceID: AudioDeviceID) -> Bool {
        if let mute = boolProperty(deviceID, selector: kAudioDevicePropertyMute) {
            return mute
        }
        // Some devices expose mute only on channel 1.
        return boolProperty(deviceID, selector: kAudioDevicePropertyMute, element: 1) ?? false
    }

    private static func volume(_ deviceID: AudioDeviceID) -> Float {
        controllableVolume(deviceID) ?? 1
    }

    private static func controllableVolume(_ deviceID: AudioDeviceID) -> Float? {
        if let volume = floatProperty(
            deviceID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        ) {
            return volume
        }
        if let volume = floatProperty(deviceID, selector: kAudioDevicePropertyVolumeScalar) {
            return volume
        }
        return floatProperty(deviceID, selector: kAudioDevicePropertyVolumeScalar, element: 1)
    }

    private static func boolProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value != 0
    }

    private static func floatProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }
}
