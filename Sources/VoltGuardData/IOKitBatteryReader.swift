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

        return Self.parseRegistryProperties(
            props,
            isClamshellClosed: Self.readClamshellState(),
            smcThermals: Self.readAppleSMCThermals()
        )
    }

    public struct SMCThermalSnapshot: Sendable {
        public let batterySensors: [Double]
        public let palmRestCelsius: Double?

        public init(batterySensors: [Double] = [], palmRestCelsius: Double? = nil) {
            self.batterySensors = batterySensors
            self.palmRestCelsius = palmRestCelsius
        }
    }

    public static func parseRegistryProperties(
        _ props: [String: Any],
        isClamshellClosed: Bool = false,
        smcThermals: SMCThermalSnapshot? = nil,
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
        let iokitTempNumber = (props["Temperature"] as? NSNumber)
            ?? (batteryData?["Temperature"] as? NSNumber)
            ?? (props["VirtualTemperature"] as? NSNumber)
        let smcSensors = (smcThermals?.batterySensors ?? []).filter { $0 > 5.0 && $0 < 95.0 }
        let tempCelsius: Double
        let tempSource: String
        let tempLive: Bool
        if let rawTemp = iokitTempNumber?.doubleValue {
            tempCelsius = rawTemp > 1000 ? (rawTemp / 10.0) - 273.15 : rawTemp
            tempSource = "IOKit SmartBattery"
            tempLive = true
        } else if !smcSensors.isEmpty {
            tempCelsius = smcSensors.reduce(0, +) / Double(smcSensors.count)
            tempSource = "AppleSMC TB0T/TB1T/TB2T"
            tempLive = true
        } else {
            tempCelsius = 21.85
            tempSource = "Fallback Unavailable"
            tempLive = false
        }

        let voltageMv = (props["Voltage"] as? NSNumber)?.doubleValue ?? 0.0
        // AppleSmartBattery reports signed 64-bit mA (sometimes printed as unsigned in ioreg).
        let amperageMa = Double((props["Amperage"] as? NSNumber)?.int64Value ?? 0)

        var adapterWatts = 0.0
        var adapterName: String?
        var adapterVoltageVolts: Double?
        var adapterCurrentAmps: Double?
        var adapterProtocol: String?
        if let adapter = props["AdapterDetails"] as? [String: Any] {
            adapterWatts = (adapter["Watts"] as? NSNumber)?.doubleValue ?? 0.0
            adapterName = (adapter["Name"] as? String) ?? (adapter["Description"] as? String)
            if let mv = (adapter["AdapterVoltage"] as? NSNumber)?.doubleValue, mv > 0 {
                adapterVoltageVolts = mv / 1000.0
            }
            if let ma = (adapter["Current"] as? NSNumber)?.doubleValue, ma > 0 {
                adapterCurrentAmps = ma / 1000.0
            }
            adapterProtocol = adapter["Description"] as? String
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
            adapterVoltageVolts: adapterVoltageVolts,
            adapterCurrentAmps: adapterCurrentAmps,
            adapterProtocol: adapterProtocol,
            deviceName: deviceName,
            permanentFailure: permanentFailure,
            temperatureSensorSource: tempSource,
            batteryThermalSensors: smcSensors.isEmpty ? (tempLive ? [tempCelsius] : []) : smcSensors,
            palmRestTemperatureCelsius: smcThermals?.palmRestCelsius,
            isTemperatureSensorLive: tempLive,
            timestamp: now
        )
    }

    private static func readAppleSMCThermals() -> SMCThermalSnapshot {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return SMCThermalSnapshot() }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            return SMCThermalSnapshot()
        }
        defer { IOServiceClose(conn) }

        var sensors: [Double] = []
        for key in ["TB0T", "TB1T", "TB2T"] {
            if let celsius = readSMCTemperature(conn: conn, key: key), celsius > 5.0 && celsius < 95.0 {
                sensors.append(celsius)
            }
        }
        let palm = readSMCTemperature(conn: conn, key: "Ts0P").flatMap { ($0 > 5.0 && $0 < 95.0) ? $0 : nil }
        return SMCThermalSnapshot(batterySensors: sensors, palmRestCelsius: palm)
    }

    private struct SMCReadKeyData {
        struct Version { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct PLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var mem: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private static func readSMCTemperature(conn: io_connect_t, key: String) -> Double? {
        let code = key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var infoIn = SMCReadKeyData()
        var infoOut = SMCReadKeyData()
        infoIn.key = code
        infoIn.data8 = 9 // kSMCGetKeyInfo
        var sz = MemoryLayout<SMCReadKeyData>.stride
        guard IOConnectCallStructMethod(conn, 2, &infoIn, sz, &infoOut, &sz) == kIOReturnSuccess,
              infoOut.result == 0,
              infoOut.keyInfo.dataSize > 0 else {
            return nil
        }

        var readIn = SMCReadKeyData()
        var readOut = SMCReadKeyData()
        readIn.key = code
        readIn.keyInfo.dataSize = infoOut.keyInfo.dataSize
        readIn.data8 = 5 // kSMCReadKey
        guard IOConnectCallStructMethod(conn, 2, &readIn, sz, &readOut, &sz) == kIOReturnSuccess,
              readOut.result == 0 else {
            return nil
        }

        let size = Int(infoOut.keyInfo.dataSize)
        let bytes = withUnsafeBytes(of: &readOut.bytes) { Array($0.prefix(size)) }
        let dt = infoOut.keyInfo.dataType
        let chars = [
            UInt8((dt >> 24) & 0xFF),
            UInt8((dt >> 16) & 0xFF),
            UInt8((dt >> 8) & 0xFF),
            UInt8(dt & 0xFF)
        ]
        let typeStr = String(bytes: chars, encoding: .ascii) ?? ""
        return Self.decodeSMCTemperature(bytes: bytes, dataType: typeStr)
    }

    public static func decodeSMCTemperature(bytes: [UInt8], dataType: String) -> Double? {
        let value: Double?
        if dataType == "flt ", bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            value = Double(Float(bitPattern: bits))
        } else if dataType == "sp78", bytes.count >= 2 {
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            value = Double(raw) / 256.0
        } else if bytes.count >= 2 {
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let dk = Double(raw)
            value = dk > 1000 ? (dk / 10.0) - 273.15 : dk
        } else {
            value = nil
        }
        guard let celsius = value, celsius > 5.0 && celsius < 95.0 else {
            return nil
        }
        return celsius
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
