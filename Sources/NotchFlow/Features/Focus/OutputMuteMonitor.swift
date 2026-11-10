import AudioToolbox
import CoreAudio
import Foundation

/// Reports when the default output device becomes silent or audible again, using CoreAudio
/// property listeners instead of polling. Callbacks arrive on the main queue.
@MainActor
final class OutputMuteMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isSilent = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceAddresses: [AudioObjectPropertyAddress] = []
    private var isRunning = false

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated {
            self?.refresh()
        }
    }

    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated {
            self?.attachToDefaultDevice()
            self?.refresh()
        }
    }

    private static func defaultOutputDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        var address = Self.defaultOutputDeviceAddress()
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultDeviceListener
        )
        attachToDefaultDevice()
        isSilent = SystemOutputAudio.isSilent
    }

    private func refresh() {
        let silent = SystemOutputAudio.isSilent
        guard silent != isSilent else { return }
        isSilent = silent
        onChange?(silent)
    }

    private func attachToDefaultDevice() {
        detachFromDevice()
        var address = Self.defaultOutputDeviceAddress()
        var newDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &newDevice
        ) == noErr, newDevice != kAudioObjectUnknown else { return }

        deviceID = newDevice
        let selectors: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyMute, 1),
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
        ]
        for (selector, element) in selectors {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(newDevice, &propertyAddress),
                  AudioObjectAddPropertyListenerBlock(newDevice, &propertyAddress, .main, listener) == noErr
            else { continue }
            deviceAddresses.append(propertyAddress)
        }
    }

    private func detachFromDevice() {
        guard deviceID != kAudioObjectUnknown else { return }
        for var address in deviceAddresses {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, listener)
        }
        deviceAddresses.removeAll()
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }
}
