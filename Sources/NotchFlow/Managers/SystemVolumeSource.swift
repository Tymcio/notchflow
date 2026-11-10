import AudioToolbox
import CoreAudio
import Foundation

/// Reports output volume / mute changes of the default output device through CoreAudio property
/// listeners (no polling). The level at start and after switching devices is only a baseline,
/// so launching the app or plugging in headphones shows nothing. Several properties fire for one
/// key press (main volume and each channel); they are coalesced into one reading per run loop
/// turn. Devices without volume control report nothing.
@MainActor
final class SystemVolumeSource: HUDLevelSource {
    var onLevel: ((HUDLevelReading) -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceAddresses: [AudioObjectPropertyAddress] = []
    private var lastLevel: SystemOutputLevel?
    private var isRunning = false
    private var isRefreshScheduled = false

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated {
            self?.scheduleRefresh()
        }
    }

    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated {
            self?.attachToDefaultDevice()
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
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        var address = Self.defaultOutputDeviceAddress()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultDeviceListener
        )
        detachFromDevice()
        lastLevel = nil
    }

    private func scheduleRefresh() {
        guard isRunning, !isRefreshScheduled else { return }
        isRefreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        isRefreshScheduled = false
        guard isRunning, deviceID != kAudioObjectUnknown,
              let level = SystemOutputAudio.outputLevel(of: deviceID),
              level != lastLevel else { return }
        lastLevel = level
        onLevel?(HUDLevelReading(kind: .volume, level: level.volume, isMuted: level.isMuted))
    }

    private func attachToDefaultDevice() {
        detachFromDevice()
        guard isRunning, let newDevice = SystemOutputAudio.defaultOutputDeviceID else { return }
        // Without a volume there is nothing to show for this device: register nothing.
        guard let level = SystemOutputAudio.outputLevel(of: newDevice) else { return }
        deviceID = newDevice
        lastLevel = level
        for (selector, element) in SystemOutputAudio.levelPropertyAddresses {
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
        lastLevel = nil
    }
}
