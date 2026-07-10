import Foundation
import IOKit.ps

struct SystemStatus: Equatable, Sendable {
    let batteryPercent: Double
    let isCharging: Bool
    let connectedBluetoothDevices: [String]
}

@MainActor
final class SystemMonitor {
    var onStatusChange: ((SystemStatus?) -> Void)?

    func refresh() {
        onStatusChange?(readStatus())
    }

    private func readStatus() -> SystemStatus? {
        let battery = readBattery()
        let bluetooth = readBluetoothDeviceNames()
        return SystemStatus(
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            connectedBluetoothDevices: bluetooth
        )
    }

    private func readBattery() -> (percent: Double, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return (0, false)
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let percent = max > 0 ? Double(current) / Double(max) : 0
        return (percent, charging)
    }

    private func readBluetoothDeviceNames() -> [String] {
        // Lightweight placeholder: Bluetooth enumeration requires IOBluetooth entitlement.
        // Premium UI can be enabled when user grants Bluetooth permission in a future build.
        []
    }
}
