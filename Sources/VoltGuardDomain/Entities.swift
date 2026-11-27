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

public enum MagSafeLEDMode: String, Codable, CaseIterable, Sendable {
    case system
    case off
    case green
    case amber
    case syncWithLimit
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

    public init(
        preset: ThemePresetID = .obsidianSlate,
        customAccentHex: String? = nil,
        cornerRadius: Double = VoltGuardLimits.defaultCornerRadius,
        surfaceOpacity: Double = VoltGuardLimits.defaultSurfaceOpacity,
        useCustomBackground: Bool = false,
        customBackgroundPath: String? = nil,
        backgroundScrimOpacity: Double = 0.70,
        backgroundBlurRadius: Double = 0.0
    ) {
        self.preset = preset
        self.customAccentHex = customAccentHex
        self.cornerRadius = min(max(cornerRadius, VoltGuardLimits.minCornerRadius), VoltGuardLimits.maxCornerRadius)
        self.surfaceOpacity = min(max(surfaceOpacity, VoltGuardLimits.minSurfaceOpacity), VoltGuardLimits.maxSurfaceOpacity)
        self.useCustomBackground = useCustomBackground
        self.customBackgroundPath = customBackgroundPath
        self.backgroundScrimOpacity = min(max(backgroundScrimOpacity, 0.0), 0.92)
        self.backgroundBlurRadius = min(max(backgroundBlurRadius, 0.0), 24.0)
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
    public let deviceName: String?
    public let permanentFailure: Bool
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
        deviceName: String? = nil,
        permanentFailure: Bool = false,
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
        self.deviceName = deviceName
        self.permanentFailure = permanentFailure
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
        lowPowerModeAlways: Bool = false
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
    public var targetLowPercent: Int
    public var holdDurationSeconds: TimeInterval

    public init(
        stage: CalibrationStage = .idle,
        stageStartedAt: Date? = nil,
        targetLowPercent: Int = 15,
        holdDurationSeconds: TimeInterval = 3600
    ) {
        self.stage = stage
        self.stageStartedAt = stageStartedAt
        self.targetLowPercent = targetLowPercent
        self.holdDurationSeconds = holdDurationSeconds
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

public struct DiagnosticsReport: Equatable, Sendable {
    public let iokitReadable: Bool
    public let smcHelperConnected: Bool
    public let launchAtLoginEnabled: Bool
    public let alertsEnabled: Bool
    public let checkedAt: Date

    public init(
        iokitReadable: Bool,
        smcHelperConnected: Bool,
        launchAtLoginEnabled: Bool,
        alertsEnabled: Bool,
        checkedAt: Date = Date()
    ) {
        self.iokitReadable = iokitReadable
        self.smcHelperConnected = smcHelperConnected
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.alertsEnabled = alertsEnabled
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
        calibrationSession: CalibrationSession = CalibrationSession()
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
    }
}
