import Foundation

public enum AppLocale: String, Codable, CaseIterable, Sendable {
    case en
    case id

    public var displayName: String {
        switch self {
        case .en: return "English"
        case .id: return "Bahasa Indonesia"
        }
    }
}

public enum SMCBackendMode: String, Codable, Equatable, Sendable {
    case unknown
    case legacy
    case firmwareManaged
    case adapterMode
    case outdatedHelper
    case unsupported
}

public enum MagSafeLEDMode: String, Codable, CaseIterable, Sendable {
    case system
    case off
    case green
    case amber
    case syncWithLimit
    case matchBattery
}

public enum BatteryColorStyle: String, Codable, CaseIterable, Sendable {
    case adaptiveSpectrum
    case thermalReactive
    case themeAccent
}

public enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable {
    case shieldBattery
    case ringGauge
    case percentagePill
    case minimalBolt
}

public enum PopoverDensity: String, Codable, CaseIterable, Sendable {
    case detailed
    case compact
}

public enum PopoverModuleID: String, Codable, CaseIterable, Identifiable, Sendable {
    case chargeControl
    case powerFlow
    case quickActions
    case calibrationAndSchedule
    case batteryHealth

    public var id: String { rawValue }
}

public enum ThemePresetID: String, Codable, CaseIterable, Identifiable, Sendable {
    case obsidianSlate
    case paperLight
    case nordicMist
    case midnightAmber

    public var id: String { rawValue }
}

public struct ThemeConfig: Codable, Equatable, Sendable {
    public var preset: ThemePresetID
    public var customAccentHex: String?
    public var cornerRadius: Double
    public var surfaceOpacity: Double
    public var useCustomBackground: Bool
    public var customBackgroundPath: String?
    public var backgroundScrimOpacity: Double
    public var backgroundBlurRadius: Double
    public var batteryColorStyle: BatteryColorStyle

    public init(
        preset: ThemePresetID = .obsidianSlate,
        customAccentHex: String? = nil,
        cornerRadius: Double = VoltGuardLimits.defaultCornerRadius,
        surfaceOpacity: Double = VoltGuardLimits.defaultSurfaceOpacity,
        useCustomBackground: Bool = false,
        customBackgroundPath: String? = nil,
        backgroundScrimOpacity: Double = 0.70,
        backgroundBlurRadius: Double = 0.0,
        batteryColorStyle: BatteryColorStyle = .adaptiveSpectrum
    ) {
        self.preset = preset
        self.customAccentHex = customAccentHex
        self.cornerRadius = min(max(cornerRadius, VoltGuardLimits.minCornerRadius), VoltGuardLimits.maxCornerRadius)
        self.surfaceOpacity = min(max(surfaceOpacity, VoltGuardLimits.minSurfaceOpacity), VoltGuardLimits.maxSurfaceOpacity)
        self.useCustomBackground = useCustomBackground
        self.customBackgroundPath = customBackgroundPath
        self.backgroundScrimOpacity = min(max(backgroundScrimOpacity, 0.0), 0.92)
        self.backgroundBlurRadius = min(max(backgroundBlurRadius, 0.0), 24.0)
        self.batteryColorStyle = batteryColorStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preset = try container.decodeIfPresent(ThemePresetID.self, forKey: .preset) ?? .obsidianSlate
        self.customAccentHex = try container.decodeIfPresent(String.self, forKey: .customAccentHex)
        let r = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? VoltGuardLimits.defaultCornerRadius
        self.cornerRadius = min(max(r, VoltGuardLimits.minCornerRadius), VoltGuardLimits.maxCornerRadius)
        let op = try container.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? VoltGuardLimits.defaultSurfaceOpacity
        self.surfaceOpacity = min(max(op, VoltGuardLimits.minSurfaceOpacity), VoltGuardLimits.maxSurfaceOpacity)
        self.useCustomBackground = try container.decodeIfPresent(Bool.self, forKey: .useCustomBackground) ?? false
        self.customBackgroundPath = try container.decodeIfPresent(String.self, forKey: .customBackgroundPath)
        let scrim = try container.decodeIfPresent(Double.self, forKey: .backgroundScrimOpacity) ?? 0.70
        self.backgroundScrimOpacity = min(max(scrim, 0.0), 0.92)
        let blur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlurRadius) ?? 0.0
        self.backgroundBlurRadius = min(max(blur, 0.0), 24.0)
        self.batteryColorStyle = try container.decodeIfPresent(BatteryColorStyle.self, forKey: .batteryColorStyle) ?? .adaptiveSpectrum
    }
}

public struct MenuBarIconConfig: Codable, Equatable, Sendable {
    public var style: MenuBarIconStyle
    public var showPercentage: Bool
    public var showWattage: Bool
    public var showTemperature: Bool
    public var showTimeRemaining: Bool

    public init(
        style: MenuBarIconStyle = .shieldBattery,
        showPercentage: Bool = true,
        showWattage: Bool = false,
        showTemperature: Bool = false,
        showTimeRemaining: Bool = false
    ) {
        self.style = style
        self.showPercentage = showPercentage
        self.showWattage = showWattage
        self.showTemperature = showTemperature
        self.showTimeRemaining = showTimeRemaining
    }
}

public struct PopoverModuleConfig: Codable, Equatable, Sendable {
    public var orderedModules: [PopoverModuleID]
    public var hiddenModules: Set<PopoverModuleID>
    public var density: PopoverDensity

    public init(
        orderedModules: [PopoverModuleID] = PopoverModuleID.allCases,
        hiddenModules: Set<PopoverModuleID> = [],
        density: PopoverDensity = .detailed
    ) {
        self.orderedModules = orderedModules
        self.hiddenModules = hiddenModules
        self.density = density
    }

    public var visibleModules: [PopoverModuleID] {
        orderedModules.filter { !hiddenModules.contains($0) }
    }
}

public enum BatteryCondition: String, Codable, Equatable, Sendable {
    case normal
    case fair
    case serviceRecommended
}

public struct BatteryTelemetry: Equatable, Sendable {
    public let percentage: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let temperatureCelsius: Double
    public let voltageVolts: Double
    public let amperageAmps: Double
    public let adapterWatts: Double
    public let cycleCount: Int
    public let designCycleCount: Int
    public let currentCapacityMah: Int?
    public let maxCapacityMah: Int
    public let designCapacityMah: Int
    public let isClamshellClosed: Bool
    public let timeRemainingMinutes: Int?
    public let adapterName: String?
    public let adapterVoltageVolts: Double?
    public let adapterCurrentAmps: Double?
    public let adapterProtocol: String?
    public let deviceName: String?
    public let permanentFailure: Bool
    public let temperatureSensorSource: String
    public let batteryThermalSensors: [Double]
    public let palmRestTemperatureCelsius: Double?
    public let isTemperatureSensorLive: Bool
    public let timestamp: Date

    public init(
        percentage: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        temperatureCelsius: Double,
        voltageVolts: Double,
        amperageAmps: Double,
        adapterWatts: Double,
        cycleCount: Int,
        designCycleCount: Int = VoltGuardLimits.defaultDesignCycleCount,
        currentCapacityMah: Int? = nil,
        maxCapacityMah: Int,
        designCapacityMah: Int,
        isClamshellClosed: Bool = false,
        timeRemainingMinutes: Int? = nil,
        adapterName: String? = nil,
        adapterVoltageVolts: Double? = nil,
        adapterCurrentAmps: Double? = nil,
        adapterProtocol: String? = nil,
        deviceName: String? = nil,
        permanentFailure: Bool = false,
        temperatureSensorSource: String = "IOKit",
        batteryThermalSensors: [Double] = [],
        palmRestTemperatureCelsius: Double? = nil,
        isTemperatureSensorLive: Bool = true,
        timestamp: Date = Date()
    ) {
        self.percentage = min(max(percentage, 0), 100)
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.temperatureCelsius = temperatureCelsius
        self.voltageVolts = voltageVolts
        self.amperageAmps = amperageAmps
        self.adapterWatts = adapterWatts
        self.cycleCount = cycleCount
        self.designCycleCount = max(designCycleCount, 1)
        self.currentCapacityMah = currentCapacityMah
        self.maxCapacityMah = maxCapacityMah
        self.designCapacityMah = max(designCapacityMah, 1)
        self.isClamshellClosed = isClamshellClosed
        self.timeRemainingMinutes = timeRemainingMinutes
        self.adapterName = adapterName
        self.adapterVoltageVolts = adapterVoltageVolts
        self.adapterCurrentAmps = adapterCurrentAmps
        self.adapterProtocol = adapterProtocol
        self.deviceName = deviceName
        self.permanentFailure = permanentFailure
        self.temperatureSensorSource = temperatureSensorSource
        self.batteryThermalSensors = batteryThermalSensors
        self.palmRestTemperatureCelsius = palmRestTemperatureCelsius
        self.isTemperatureSensorLive = isTemperatureSensorLive
        self.timestamp = timestamp
    }

    public var healthPercent: Int {
        // Round to nearest integer to match macOS System Information Maximum Capacity.
        let raw = (Double(maxCapacityMah) / Double(designCapacityMah)) * 100.0
        return min(max(Int(raw.rounded()), 0), 100)
    }

    public var batteryCondition: BatteryCondition {
        if permanentFailure || healthPercent < VoltGuardLimits.healthServiceThresholdPercent {
            return .serviceRecommended
        }
        if healthPercent < VoltGuardLimits.healthFairThresholdPercent {
            return .fair
        }
        return .normal
    }
}

public struct PowerFlowMetrics: Equatable, Sendable {
    public let adapterInputWatts: Double
    public let batteryNetWatts: Double
    public let systemLoadWatts: Double

    public init(adapterInputWatts: Double, batteryNetWatts: Double, systemLoadWatts: Double) {
        self.adapterInputWatts = adapterInputWatts
        self.batteryNetWatts = batteryNetWatts
        self.systemLoadWatts = systemLoadWatts
    }
}

public struct ChargePolicy: Codable, Equatable, Sendable {
    public var limitPercent: Int
    public var manualDischarge: Bool
    public var automaticDischarge: Bool
    public var dischargeInClamshell: Bool
    public var heatProtectionEnabled: Bool
    public var maxTemperatureCelsius: Double
    public var sailingModeEnabled: Bool
    public var sailingDeltaPercent: Int
    public var magSafeLEDMode: MagSafeLEDMode
    public var topUpActive: Bool
    public var sleepControlEnabled: Bool
    public var stopChargingWhenSleeping: Bool
    public var lowPowerModeOnBattery: Bool
    public var lowPowerModeAlways: Bool
    public var restoreDefaultOnQuit: Bool

    public init(
        limitPercent: Int = VoltGuardLimits.defaultLimitPercent,
        manualDischarge: Bool = false,
        automaticDischarge: Bool = false,
        dischargeInClamshell: Bool = false,
        heatProtectionEnabled: Bool = true,
        maxTemperatureCelsius: Double = VoltGuardLimits.defaultMaxTemperatureCelsius,
        sailingModeEnabled: Bool = false,
        sailingDeltaPercent: Int = VoltGuardLimits.defaultSailingDeltaPercent,
        magSafeLEDMode: MagSafeLEDMode = .syncWithLimit,
        topUpActive: Bool = false,
        sleepControlEnabled: Bool = true,
        stopChargingWhenSleeping: Bool = false,
        lowPowerModeOnBattery: Bool = false,
        lowPowerModeAlways: Bool = false,
        restoreDefaultOnQuit: Bool = true
    ) {
        self.limitPercent = min(max(limitPercent, VoltGuardLimits.minLimitPercent), VoltGuardLimits.maxLimitPercent)
        self.manualDischarge = manualDischarge
        self.automaticDischarge = automaticDischarge
        self.dischargeInClamshell = dischargeInClamshell
        self.heatProtectionEnabled = heatProtectionEnabled
        self.maxTemperatureCelsius = min(max(maxTemperatureCelsius, VoltGuardLimits.minTemperatureCelsius), VoltGuardLimits.maxTemperatureCelsius)
        self.sailingModeEnabled = sailingModeEnabled
        self.sailingDeltaPercent = min(max(sailingDeltaPercent, VoltGuardLimits.minSailingDeltaPercent), VoltGuardLimits.maxSailingDeltaPercent)
        self.magSafeLEDMode = magSafeLEDMode
        self.topUpActive = topUpActive
        self.sleepControlEnabled = sleepControlEnabled
        self.stopChargingWhenSleeping = stopChargingWhenSleeping
        self.lowPowerModeOnBattery = lowPowerModeOnBattery
        self.lowPowerModeAlways = lowPowerModeAlways
        self.restoreDefaultOnQuit = restoreDefaultOnQuit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChargePolicy()
        self.init(
            limitPercent: try c.decodeIfPresent(Int.self, forKey: .limitPercent) ?? d.limitPercent,
            manualDischarge: try c.decodeIfPresent(Bool.self, forKey: .manualDischarge) ?? d.manualDischarge,
            automaticDischarge: try c.decodeIfPresent(Bool.self, forKey: .automaticDischarge) ?? d.automaticDischarge,
            dischargeInClamshell: try c.decodeIfPresent(Bool.self, forKey: .dischargeInClamshell) ?? d.dischargeInClamshell,
            heatProtectionEnabled: try c.decodeIfPresent(Bool.self, forKey: .heatProtectionEnabled) ?? d.heatProtectionEnabled,
            maxTemperatureCelsius: try c.decodeIfPresent(Double.self, forKey: .maxTemperatureCelsius) ?? d.maxTemperatureCelsius,
            sailingModeEnabled: try c.decodeIfPresent(Bool.self, forKey: .sailingModeEnabled) ?? d.sailingModeEnabled,
            sailingDeltaPercent: try c.decodeIfPresent(Int.self, forKey: .sailingDeltaPercent) ?? d.sailingDeltaPercent,
            magSafeLEDMode: try c.decodeIfPresent(MagSafeLEDMode.self, forKey: .magSafeLEDMode) ?? d.magSafeLEDMode,
            topUpActive: try c.decodeIfPresent(Bool.self, forKey: .topUpActive) ?? d.topUpActive,
            sleepControlEnabled: try c.decodeIfPresent(Bool.self, forKey: .sleepControlEnabled) ?? d.sleepControlEnabled,
            stopChargingWhenSleeping: try c.decodeIfPresent(Bool.self, forKey: .stopChargingWhenSleeping) ?? d.stopChargingWhenSleeping,
            lowPowerModeOnBattery: try c.decodeIfPresent(Bool.self, forKey: .lowPowerModeOnBattery) ?? d.lowPowerModeOnBattery,
            lowPowerModeAlways: try c.decodeIfPresent(Bool.self, forKey: .lowPowerModeAlways) ?? d.lowPowerModeAlways,
            restoreDefaultOnQuit: try c.decodeIfPresent(Bool.self, forKey: .restoreDefaultOnQuit) ?? d.restoreDefaultOnQuit
        )
    }
}

public enum CalibrationStage: String, Codable, Equatable, Sendable {
    case idle
    case chargingToFull
    case holdingFull
    case dischargingToLow
    case holdingLow
    case restoringLimit
    case completed
}

public struct CalibrationSession: Codable, Equatable, Sendable {
    public var stage: CalibrationStage
    public var stageStartedAt: Date?
    public var startedAt: Date?
    public var targetLowPercent: Int
    public var holdDurationSeconds: TimeInterval
    public var beforeMaxCapacityMah: Int?
    public var beforeHealthPercent: Int?
    public var beforeCycleCount: Int?

    public init(
        stage: CalibrationStage = .idle,
        stageStartedAt: Date? = nil,
        startedAt: Date? = nil,
        targetLowPercent: Int = 15,
        holdDurationSeconds: TimeInterval = 3600,
        beforeMaxCapacityMah: Int? = nil,
        beforeHealthPercent: Int? = nil,
        beforeCycleCount: Int? = nil
    ) {
        self.stage = stage
        self.stageStartedAt = stageStartedAt
        self.startedAt = startedAt
        self.targetLowPercent = targetLowPercent
        self.holdDurationSeconds = holdDurationSeconds
        self.beforeMaxCapacityMah = beforeMaxCapacityMah
        self.beforeHealthPercent = beforeHealthPercent
        self.beforeCycleCount = beforeCycleCount
    }

    public var isActive: Bool {
        stage != .idle && stage != .completed
    }

    public func remainingHoldSeconds(at now: Date = Date()) -> TimeInterval? {
        guard stage == .holdingFull || stage == .holdingLow, let started = stageStartedAt else {
            return nil
        }
        return max(holdDurationSeconds - now.timeIntervalSince(started), 0)
    }
}

public struct CalibrationResultRecord: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let completedAt: Date
    public let beforeMaxCapacityMah: Int
    public let afterMaxCapacityMah: Int
    public let beforeHealthPercent: Int
    public let afterHealthPercent: Int
    public let beforeCycleCount: Int
    public let afterCycleCount: Int

    public init(
        startedAt: Date,
        completedAt: Date = Date(),
        beforeMaxCapacityMah: Int,
        afterMaxCapacityMah: Int,
        beforeHealthPercent: Int,
        afterHealthPercent: Int,
        beforeCycleCount: Int,
        afterCycleCount: Int
    ) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.beforeMaxCapacityMah = beforeMaxCapacityMah
        self.afterMaxCapacityMah = afterMaxCapacityMah
        self.beforeHealthPercent = beforeHealthPercent
        self.afterHealthPercent = afterHealthPercent
        self.beforeCycleCount = beforeCycleCount
        self.afterCycleCount = afterCycleCount
    }

    public var deltaMah: Int { afterMaxCapacityMah - beforeMaxCapacityMah }
    public var deltaHealthPercent: Int { afterHealthPercent - beforeHealthPercent }
}

public struct AppReleaseChangelogEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let version: String
    public let date: String
    public let titleEN: String
    public let titleID: String
    public let highlightsEN: [String]
    public let highlightsID: [String]

    public init(
        version: String,
        date: String,
        titleEN: String,
        titleID: String,
        highlightsEN: [String],
        highlightsID: [String]
    ) {
        self.id = version
        self.version = version
        self.date = date
        self.titleEN = titleEN
        self.titleID = titleID
        self.highlightsEN = highlightsEN
        self.highlightsID = highlightsID
    }
}

public enum AppUpdateStage: Equatable, Sendable {
    case idle
    case checking
    case available
    case upToDate
    case downloading(Double)
    case installing
    case cleaningUp
    case completed
    case failed(String)
}

public struct AppUpdateCheckResult: Equatable, Sendable {
    public let currentVersion: String
    public let latestVersion: String
    public let latestBuild: String
    public let publishedAt: String
    public let isUpdateAvailable: Bool
    public let dmgDownloadURL: String?
    public let latestChangesEN: [String]
    public let latestFixesEN: [String]
    public let latestChangesID: [String]
    public let latestFixesID: [String]
    public let checkedAt: Date

    public init(
        currentVersion: String,
        latestVersion: String,
        latestBuild: String = AppReleaseInfo.buildNumber,
        publishedAt: String = AppReleaseInfo.latestPublishedDate,
        isUpdateAvailable: Bool,
        dmgDownloadURL: String?,
        latestChangesEN: [String] = AppReleaseInfo.latestChangesEN,
        latestFixesEN: [String] = AppReleaseInfo.latestFixesEN,
        latestChangesID: [String] = AppReleaseInfo.latestChangesID,
        latestFixesID: [String] = AppReleaseInfo.latestFixesID,
        checkedAt: Date = Date()
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.latestBuild = latestBuild
        self.publishedAt = publishedAt
        self.isUpdateAvailable = isUpdateAvailable
        self.dmgDownloadURL = dmgDownloadURL
        self.latestChangesEN = latestChangesEN
        self.latestFixesEN = latestFixesEN
        self.latestChangesID = latestChangesID
        self.latestFixesID = latestFixesID
        self.checkedAt = checkedAt
    }
}

public enum AppReleaseInfo {
    public static let currentVersion = "1.2.0"
    public static let buildNumber = "3"
    public static let latestPublishedDate = "2026-11-27"
    public static let websiteURL = "https://voltguard-mocha.vercel.app"
    public static let feedURL = "https://voltguard-mocha.vercel.app/appcast.json"
    public static let dmgURL = "https://voltguard-mocha.vercel.app/downloads/VoltGuard.dmg"

    public static let latestChangesEN: [String] = [
        "Interactive animated Thermal Zone card with inline limit controls and sensor breakdown",
        "Before vs After calibration capacity comparison card with expected outcome guide",
        "Restore System Charging on Quit toggle to resume normal 100% charging when closed",
        "Dedicated Software Update tab with automatic install and DMG cleanup"
    ]

    public static let latestFixesEN: [String] = [
        "Fixed battery temperature stuck at 21.9 C on macOS 27 and modern Apple Silicon Macs",
        "Improved visual polish and modern macOS system compatibility"
    ]

    public static let latestChangesID: [String] = [
        "Kartu Thermal Zone interaktif beranimasi dengan atur batas suhu langsung",
        "Kartu perbandingan kapasitas Before vs After kalibrasi beserta penjelasan hasilnya",
        "Opsi Restore System Charging on Quit agar Mac mengisi normal 100% saat app ditutup",
        "Halaman Pembaruan Aplikasi tersendiri dengan pasang otomatis dan hapus file DMG"
    ]

    public static let latestFixesID: [String] = [
        "Memperbaiki suhu baterai yang macet di 21.9 C pada macOS 27 dan Mac Apple Silicon terbaru",
        "Peningkatan tampilan dan kompatibilitas penuh dengan macOS modern"
    ]

    public static let changelog: [AppReleaseChangelogEntry] = [
        AppReleaseChangelogEntry(
            version: "1.2.0",
            date: "2026-11-27",
            titleEN: "What's New & Fixes in v1.2.0",
            titleID: "Perubahan & Perbaikan Versi 1.2.0",
            highlightsEN: latestChangesEN + latestFixesEN,
            highlightsID: latestChangesID + latestFixesID
        )
    ]

    public static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { raw in
            raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .compactMap { Int($0.filter(\.isNumber)) }
        }
        let a = parse(candidate)
        let b = parse(current)
        let count = max(a.count, b.count)
        for idx in 0..<count {
            let av = idx < a.count ? a[idx] : 0
            let bv = idx < b.count ? b[idx] : 0
            if av != bv { return av > bv }
        }
        return false
    }
}

public struct BatteryHealthSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String // YYYY-MM-DD
    public let date: Date
    public let healthPercent: Int
    public let cycleCount: Int
    public let peakTemperatureCelsius: Double

    public init(
        id: String,
        date: Date,
        healthPercent: Int,
        cycleCount: Int,
        peakTemperatureCelsius: Double
    ) {
        self.id = id
        self.date = date
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.peakTemperatureCelsius = peakTemperatureCelsius
    }
}

public struct MacHardwareProfile: Codable, Equatable, Sendable {
    public let modelIdentifier: String
    public let architecture: String
    public let macOSVersionString: String
    public let macOSMajorVersion: Int
    public let isDesktopMac: Bool
    public let isAppleSilicon: Bool
    public let supportsMagSafeLED: Bool
    public let supportsLowPowerMode: Bool

    public init(
        modelIdentifier: String,
        architecture: String,
        macOSVersionString: String,
        macOSMajorVersion: Int,
        isDesktopMac: Bool,
        isAppleSilicon: Bool,
        supportsMagSafeLED: Bool,
        supportsLowPowerMode: Bool
    ) {
        self.modelIdentifier = modelIdentifier
        self.architecture = architecture
        self.macOSVersionString = macOSVersionString
        self.macOSMajorVersion = macOSMajorVersion
        self.isDesktopMac = isDesktopMac
        self.isAppleSilicon = isAppleSilicon
        self.supportsMagSafeLED = supportsMagSafeLED
        self.supportsLowPowerMode = supportsLowPowerMode
    }

    public static func detectCurrent(
        writableKeys: [String] = [],
        hasBatteryService: Bool = true,
        modelOverride: String? = nil
    ) -> MacHardwareProfile {
        let model = modelOverride ?? readSysctlString("hw.model") ?? "Mac"
        #if arch(arm64)
        let arch = "arm64"
        let appleSilicon = true
        #else
        let arch = "x86_64"
        let appleSilicon = false
        #endif
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        let verString = "\(ver.majorVersion).\(ver.minorVersion).\(ver.patchVersion)"
        let lowerModel = model.lowercased()
        let modelIsDesktop = lowerModel.hasPrefix("imac")
            || lowerModel.hasPrefix("macmini")
            || lowerModel.hasPrefix("macstudio")
            || lowerModel.hasPrefix("macpro")
            || (lowerModel.hasPrefix("mac") && !hasBatteryService)
        let desktop = modelIsDesktop || !hasBatteryService

        let magSafeSupported: Bool
        if !writableKeys.isEmpty {
            magSafeSupported = writableKeys.contains("ACLC")
        } else if desktop || !appleSilicon {
            magSafeSupported = false
        } else {
            // Known USB-C-only Apple Silicon models without MagSafe 3 LED port
            let usbCOnlyModels: Set<String> = ["macbookair10,1", "macbookpro17,1", "mac14,7"]
            magSafeSupported = !usbCOnlyModels.contains(lowerModel)
        }

        let lowPowerSupported = !desktop && (appleSilicon || ver.majorVersion >= 13)
        return MacHardwareProfile(
            modelIdentifier: model,
            architecture: arch,
            macOSVersionString: verString,
            macOSMajorVersion: ver.majorVersion,
            isDesktopMac: desktop,
            isAppleSilicon: appleSilicon,
            supportsMagSafeLED: magSafeSupported,
            supportsLowPowerMode: lowPowerSupported
        )
    }

    private static func readSysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

public struct FeatureCapabilityStatus: Codable, Equatable, Sendable {
    public let supported: Bool
    public let reasonCode: String

    public init(supported: Bool, reasonCode: String = "ok") {
        self.supported = supported
        self.reasonCode = reasonCode
    }
}

public struct CachedCompatibilityReport: Codable, Equatable, Sendable {
    public let fingerprint: String
    public let hardwareProfile: MacHardwareProfile
    public let backendMode: SMCBackendMode
    public let writableKeys: [String]
    public let helperConnected: Bool
    public let chargeLimit: FeatureCapabilityStatus
    public let discharge: FeatureCapabilityStatus
    public let bypassCharging: FeatureCapabilityStatus
    public let magSafeLED: FeatureCapabilityStatus
    public let lowPowerMode: FeatureCapabilityStatus
    public let checkedAt: Date

    public init(
        fingerprint: String,
        hardwareProfile: MacHardwareProfile,
        backendMode: SMCBackendMode,
        writableKeys: [String],
        helperConnected: Bool,
        chargeLimit: FeatureCapabilityStatus,
        discharge: FeatureCapabilityStatus,
        bypassCharging: FeatureCapabilityStatus,
        magSafeLED: FeatureCapabilityStatus,
        lowPowerMode: FeatureCapabilityStatus,
        checkedAt: Date = Date()
    ) {
        self.fingerprint = fingerprint
        self.hardwareProfile = hardwareProfile
        self.backendMode = backendMode
        self.writableKeys = writableKeys
        self.helperConnected = helperConnected
        self.chargeLimit = chargeLimit
        self.discharge = discharge
        self.bypassCharging = bypassCharging
        self.magSafeLED = magSafeLED
        self.lowPowerMode = lowPowerMode
        self.checkedAt = checkedAt
    }

    public static func makeFingerprint(
        profile: MacHardwareProfile,
        backendMode: SMCBackendMode,
        writableKeys: [String],
        helperConnected: Bool,
        helperSignature: String
    ) -> String {
        let sortedKeys = writableKeys.sorted().joined(separator: ",")
        return "\(profile.modelIdentifier)|\(profile.architecture)|\(profile.macOSVersionString)|\(profile.isDesktopMac)|\(helperConnected)|\(backendMode.rawValue)|\(sortedKeys)|\(helperSignature)"
    }

    public static func evaluateOnce(
        profile: MacHardwareProfile,
        backendMode: SMCBackendMode,
        writableKeys: [String],
        helperConnected: Bool,
        helperSignature: String,
        now: Date = Date()
    ) -> CachedCompatibilityReport {
        let fp = makeFingerprint(
            profile: profile,
            backendMode: backendMode,
            writableKeys: writableKeys,
            helperConnected: helperConnected,
            helperSignature: helperSignature
        )

        if profile.isDesktopMac {
            let desktopStatus = FeatureCapabilityStatus(supported: false, reasonCode: "no_battery_desktop")
            return CachedCompatibilityReport(
                fingerprint: fp,
                hardwareProfile: profile,
                backendMode: backendMode,
                writableKeys: writableKeys,
                helperConnected: helperConnected,
                chargeLimit: desktopStatus,
                discharge: desktopStatus,
                bypassCharging: desktopStatus,
                magSafeLED: desktopStatus,
                lowPowerMode: FeatureCapabilityStatus(supported: false, reasonCode: "no_battery_desktop"),
                checkedAt: now
            )
        }

        let unsupportedBySMC = helperConnected && backendMode == .unsupported
        let chargeLimitStatus = unsupportedBySMC
            ? FeatureCapabilityStatus(supported: false, reasonCode: "smc_keys_locked")
            : FeatureCapabilityStatus(supported: true)

        let dischargeSupported: Bool = {
            if unsupportedBySMC { return false }
            if !writableKeys.isEmpty {
                let dischargeKeys: Set<String> = ["CHIE", "CH0I", "CH0J", "CH0K", "BCLM"]
                return writableKeys.contains { dischargeKeys.contains($0) }
            }
            return true
        }()
        let dischargeStatus = dischargeSupported
            ? FeatureCapabilityStatus(supported: true)
            : FeatureCapabilityStatus(supported: false, reasonCode: "discharge_keys_unavailable")

        let bypassStatus: FeatureCapabilityStatus
        if unsupportedBySMC {
            bypassStatus = FeatureCapabilityStatus(supported: false, reasonCode: "smc_keys_locked")
        } else if backendMode == .adapterMode {
            bypassStatus = FeatureCapabilityStatus(supported: false, reasonCode: "adapter_mode_hysteresis")
        } else {
            bypassStatus = FeatureCapabilityStatus(supported: true)
        }

        let magSafeStatus: FeatureCapabilityStatus
        if !profile.supportsMagSafeLED {
            magSafeStatus = FeatureCapabilityStatus(supported: false, reasonCode: "no_magsafe3_hardware")
        } else if backendMode == .adapterMode {
            // CHIE=0x08 cuts external adapter power rail, preventing MagSafe 3 LED plug updates.
            magSafeStatus = FeatureCapabilityStatus(supported: false, reasonCode: "adapter_mode_cuts_magsafe")
        } else if !writableKeys.isEmpty && !writableKeys.contains("ACLC") {
            magSafeStatus = FeatureCapabilityStatus(supported: false, reasonCode: "no_magsafe3_hardware")
        } else {
            magSafeStatus = FeatureCapabilityStatus(supported: true)
        }

        let lowPowerStatus = profile.supportsLowPowerMode
            ? FeatureCapabilityStatus(supported: true)
            : FeatureCapabilityStatus(supported: false, reasonCode: "low_power_unsupported")

        return CachedCompatibilityReport(
            fingerprint: fp,
            hardwareProfile: profile,
            backendMode: backendMode,
            writableKeys: writableKeys,
            helperConnected: helperConnected,
            chargeLimit: chargeLimitStatus,
            discharge: dischargeStatus,
            bypassCharging: bypassStatus,
            magSafeLED: magSafeStatus,
            lowPowerMode: lowPowerStatus,
            checkedAt: now
        )
    }
}

public struct DiagnosticsReport: Equatable, Sendable {
    public let iokitReadable: Bool
    public let smcHelperConnected: Bool
    public let smcHelperUpToDate: Bool
    public let appleSMCReadable: Bool
    public let launchAtLoginEnabled: Bool
    public let alertsEnabled: Bool
    public let sensorSummary: String?
    public let crashReportCount: Int
    public let latestCrashSummary: String?
    public let smcBackendMode: SMCBackendMode
    public let writableKeys: [String]
    public let hardwareProfile: MacHardwareProfile
    public let temperatureSensorLive: Bool
    public let temperatureSummary: String?
    public let checkedAt: Date

    public init(
        iokitReadable: Bool,
        smcHelperConnected: Bool,
        smcHelperUpToDate: Bool = true,
        appleSMCReadable: Bool = true,
        launchAtLoginEnabled: Bool,
        alertsEnabled: Bool,
        sensorSummary: String? = nil,
        crashReportCount: Int = 0,
        latestCrashSummary: String? = nil,
        smcBackendMode: SMCBackendMode = .unknown,
        writableKeys: [String] = [],
        hardwareProfile: MacHardwareProfile = .detectCurrent(),
        temperatureSensorLive: Bool = true,
        temperatureSummary: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.iokitReadable = iokitReadable
        self.smcHelperConnected = smcHelperConnected
        self.smcHelperUpToDate = smcHelperUpToDate
        self.appleSMCReadable = appleSMCReadable
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.alertsEnabled = alertsEnabled
        self.sensorSummary = sensorSummary
        self.crashReportCount = crashReportCount
        self.latestCrashSummary = latestCrashSummary
        self.smcBackendMode = smcBackendMode
        self.writableKeys = writableKeys
        self.hardwareProfile = hardwareProfile
        self.temperatureSensorLive = temperatureSensorLive
        self.temperatureSummary = temperatureSummary
        self.checkedAt = checkedAt
    }
}

public enum ScheduleAction: String, Codable, CaseIterable, Sendable {
    case setLimit80
    case topUp100
    case enableDischarge
    case disableDischarge
}

public struct ScheduleRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var hour: Int
    public var minute: Int
    public var weekdays: Set<Int> // 1 = Sunday ... 7 = Saturday
    public var action: ScheduleAction
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        hour: Int,
        minute: Int,
        weekdays: Set<Int> = [2, 3, 4, 5, 6],
        action: ScheduleAction,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = weekdays
        self.action = action
        self.isEnabled = isEnabled
    }
}

public struct CustomBatteryProfile: Codable, Equatable, Sendable {
    public var limitPercent: Int
    public var sailingModeEnabled: Bool
    public var sailingDeltaPercent: Int
    public var maxTemperatureCelsius: Double

    public init(
        limitPercent: Int = VoltGuardLimits.defaultLimitPercent,
        sailingModeEnabled: Bool = false,
        sailingDeltaPercent: Int = VoltGuardLimits.defaultSailingDeltaPercent,
        maxTemperatureCelsius: Double = VoltGuardLimits.defaultMaxTemperatureCelsius
    ) {
        self.limitPercent = min(max(limitPercent, VoltGuardLimits.minLimitPercent), VoltGuardLimits.maxLimitPercent)
        self.sailingModeEnabled = sailingModeEnabled
        self.sailingDeltaPercent = min(max(sailingDeltaPercent, VoltGuardLimits.minSailingDeltaPercent), VoltGuardLimits.maxSailingDeltaPercent)
        self.maxTemperatureCelsius = min(max(maxTemperatureCelsius, VoltGuardLimits.minTemperatureCelsius), VoltGuardLimits.maxTemperatureCelsius)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var policy: ChargePolicy
    public var schedules: [ScheduleRule]
    public var theme: ThemeConfig
    public var menuBarIcon: MenuBarIconConfig
    public var popoverLayout: PopoverModuleConfig
    public var locale: AppLocale
    public var launchAtLogin: Bool
    public var alertsEnabled: Bool
    public var customProfile: CustomBatteryProfile?
    public var calibrationSession: CalibrationSession
    public var lastCalibrationResult: CalibrationResultRecord?
    public var cachedCompatibility: CachedCompatibilityReport?

    public init(
        policy: ChargePolicy = ChargePolicy(),
        schedules: [ScheduleRule] = [],
        theme: ThemeConfig = ThemeConfig(),
        menuBarIcon: MenuBarIconConfig = MenuBarIconConfig(),
        popoverLayout: PopoverModuleConfig = PopoverModuleConfig(),
        locale: AppLocale = .en,
        launchAtLogin: Bool = false,
        alertsEnabled: Bool = true,
        customProfile: CustomBatteryProfile? = nil,
        calibrationSession: CalibrationSession = CalibrationSession(),
        lastCalibrationResult: CalibrationResultRecord? = nil,
        cachedCompatibility: CachedCompatibilityReport? = nil
    ) {
        self.policy = policy
        self.schedules = schedules
        self.theme = theme
        self.menuBarIcon = menuBarIcon
        self.popoverLayout = popoverLayout
        self.locale = locale
        self.launchAtLogin = launchAtLogin
        self.alertsEnabled = alertsEnabled
        self.customProfile = customProfile
        self.calibrationSession = calibrationSession
        self.lastCalibrationResult = lastCalibrationResult
        self.cachedCompatibility = cachedCompatibility
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.policy = try container.decodeIfPresent(ChargePolicy.self, forKey: .policy) ?? ChargePolicy()
        self.schedules = try container.decodeIfPresent([ScheduleRule].self, forKey: .schedules) ?? []
        self.theme = try container.decodeIfPresent(ThemeConfig.self, forKey: .theme) ?? ThemeConfig()
        self.menuBarIcon = try container.decodeIfPresent(MenuBarIconConfig.self, forKey: .menuBarIcon) ?? MenuBarIconConfig()
        self.popoverLayout = try container.decodeIfPresent(PopoverModuleConfig.self, forKey: .popoverLayout) ?? PopoverModuleConfig()
        self.locale = try container.decodeIfPresent(AppLocale.self, forKey: .locale) ?? .en
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.alertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        self.customProfile = try container.decodeIfPresent(CustomBatteryProfile.self, forKey: .customProfile)
        self.calibrationSession = try container.decodeIfPresent(CalibrationSession.self, forKey: .calibrationSession) ?? CalibrationSession()
        self.lastCalibrationResult = try container.decodeIfPresent(CalibrationResultRecord.self, forKey: .lastCalibrationResult)
        self.cachedCompatibility = try container.decodeIfPresent(CachedCompatibilityReport.self, forKey: .cachedCompatibility)
    }
}
