import Foundation
import IOKit
import VoltGuardDomain

public enum BatteryReaderError: Error, LocalizedError {
    case smartBatteryServiceUnavailable
    case propertiesUnavailable

    public var errorDescription: String? {
        switch self {
        case .smartBatteryServiceUnavailable:
            return "AppleSmartBattery IOKit service is unavailable."
        case .propertiesUnavailable:
            return "Unable to read battery properties from IOKit."
        }
    }
}

public final class IOKitBatteryReader: BatteryReadingGateway, @unchecked Sendable {
    public init() {}

    public func readTelemetry() throws -> BatteryTelemetry {
        let matching = IOServiceMatching(DataConstants.IOKit.smartBatteryService)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            throw BatteryReaderError.smartBatteryServiceUnavailable
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            throw BatteryReaderError.propertiesUnavailable
        }

        return Self.parseRegistryProperties(props, isClamshellClosed: Self.readClamshellState())
    }

    public static func parseRegistryProperties(
        _ props: [String: Any],
        isClamshellClosed: Bool = false,
        now: Date = Date()
    ) -> BatteryTelemetry {
        let currentCap = (props["CurrentCapacity"] as? NSNumber)?.intValue ?? 0
        let maxCap = (props["MaxCapacity"] as? NSNumber)?.intValue ?? 100
        let batteryData = props["BatteryData"] as? [String: Any]
        let rawCurrentMah = (props["AppleRawCurrentCapacity"] as? NSNumber)?.intValue
            ?? (batteryData?["AppleRawCurrentCapacity"] as? NSNumber)?.intValue
            ?? (batteryData?["RemainingCapacity"] as? NSNumber)?.intValue
        let rawMaxMah = (props["NominalChargeCapacity"] as? NSNumber)?.intValue
            ?? (batteryData?["NominalChargeCapacity"] as? NSNumber)?.intValue
            ?? (props["AppleRawMaxCapacity"] as? NSNumber)?.intValue
            ?? (batteryData?["AppleRawMaxCapacity"] as? NSNumber)?.intValue
            ?? maxCap
        let designMah = (props["DesignCapacity"] as? NSNumber)?.intValue
            ?? (batteryData?["DesignCapacity"] as? NSNumber)?.intValue
            ?? max(rawMaxMah, 1)

        let percentage: Int
        if let pct = (props["CurrentCapacity"] as? NSNumber)?.intValue, maxCap == 100 {
            percentage = pct
        } else if maxCap > 0 {
            percentage = Int((Double(currentCap) / Double(maxCap)) * 100.0)
        } else {
            percentage = 0
        }

        let isCharging = (props["IsCharging"] as? Bool) ?? false
        let isPluggedIn = (props["ExternalConnected"] as? Bool) ?? false
        let rawTemp = (props["Temperature"] as? NSNumber)?.doubleValue ?? 2950.0
        // AppleSmartBattery reports temperature in deci-Kelvin (0.1 K).
        let tempCelsius = rawTemp > 1000 ? (rawTemp / 10.0) - 273.15 : rawTemp

        let voltageMv = (props["Voltage"] as? NSNumber)?.doubleValue ?? 0.0
        // AppleSmartBattery reports signed 64-bit mA (sometimes printed as unsigned in ioreg).
        let amperageMa = Double((props["Amperage"] as? NSNumber)?.int64Value ?? 0)

        var adapterWatts = 0.0
        var adapterName: String?
        if let adapter = props["AdapterDetails"] as? [String: Any] {
            adapterWatts = (adapter["Watts"] as? NSNumber)?.doubleValue ?? 0.0
            adapterName = (adapter["Name"] as? String) ?? (adapter["Description"] as? String)
        }

        let cycleCount = (props["CycleCount"] as? NSNumber)?.intValue ?? 0
        let designCycleCount = (props["DesignCycleCount9C"] as? NSNumber)?.intValue
            ?? VoltGuardLimits.defaultDesignCycleCount
        let deviceName = props["DeviceName"] as? String
        let permanentFailure = ((props["PermanentFailureStatus"] as? NSNumber)?.intValue ?? 0) != 0
        let timeRemaining = (props["TimeRemaining"] as? NSNumber)?.intValue
        let validTime = (timeRemaining != nil && timeRemaining! > 0 && timeRemaining! < 6000) ? timeRemaining : nil

        return BatteryTelemetry(
            percentage: percentage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            temperatureCelsius: tempCelsius,
            voltageVolts: voltageMv / 1000.0,
            amperageAmps: amperageMa / 1000.0,
            adapterWatts: adapterWatts,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            currentCapacityMah: rawCurrentMah,
            maxCapacityMah: rawMaxMah,
            designCapacityMah: designMah,
            isClamshellClosed: isClamshellClosed,
            timeRemainingMinutes: validTime,
            adapterName: adapterName,
            deviceName: deviceName,
            permanentFailure: permanentFailure,
            timestamp: now
        )
    }

    private static func readClamshellState() -> Bool {
        let matching = IOServiceMatching("IOPMrootDomain")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) {
            return (prop.takeRetainedValue() as? Bool) ?? false
        }
        return false
    }
}
