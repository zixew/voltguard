import Foundation

public enum BatteryProfileTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case travel
    case balanced
    case deskDocked
    case maxLifespan

    public var id: String { rawValue }
}

public enum RecommendationReason: String, Equatable, Sendable {
    case highTemperature
    case clamshellDocked
    case lowBatteryUnplugged
    case dailyBalanced
}

public struct ProfileRecommendation: Equatable, Sendable {
    public let tier: BatteryProfileTier
    public let reason: RecommendationReason
    public let isAlreadyApplied: Bool

    public init(tier: BatteryProfileTier, reason: RecommendationReason, isAlreadyApplied: Bool) {
        self.tier = tier
        self.reason = reason
        self.isAlreadyApplied = isAlreadyApplied
    }
}

public struct RecommendProfileUseCase: Sendable {
    public init() {}

    public func recommend(telemetry: BatteryTelemetry, currentPolicy: ChargePolicy) -> ProfileRecommendation {
        let tier: BatteryProfileTier
        let reason: RecommendationReason

        if telemetry.isPluggedIn && telemetry.temperatureCelsius >= VoltGuardLimits.defaultMaxTemperatureCelsius {
            tier = .maxLifespan
            reason = .highTemperature
        } else if telemetry.isPluggedIn && telemetry.isClamshellClosed {
            tier = .deskDocked
            reason = .clamshellDocked
        } else if !telemetry.isPluggedIn && telemetry.percentage <= ProfilePresetConstants.lowBatteryTravelThreshold {
            tier = .travel
            reason = .lowBatteryUnplugged
        } else {
            tier = .balanced
            reason = .dailyBalanced
        }

        let targetPolicy = policy(for: tier, preserving: currentPolicy)
        let alreadyApplied = currentPolicy.limitPercent == targetPolicy.limitPercent
            && currentPolicy.sailingModeEnabled == targetPolicy.sailingModeEnabled
            && currentPolicy.automaticDischarge == targetPolicy.automaticDischarge
            && currentPolicy.heatProtectionEnabled == targetPolicy.heatProtectionEnabled

        return ProfileRecommendation(tier: tier, reason: reason, isAlreadyApplied: alreadyApplied)
    }

    public func policy(for tier: BatteryProfileTier, preserving base: ChargePolicy) -> ChargePolicy {
        var next = base
        next.topUpActive = false
        next.manualDischarge = false

        switch tier {
        case .travel:
            next.limitPercent = ProfilePresetConstants.travelLimit
            next.sailingModeEnabled = false
            next.automaticDischarge = false
            next.dischargeInClamshell = false
            next.heatProtectionEnabled = true
            next.maxTemperatureCelsius = ProfilePresetConstants.travelMaxTemp
            next.lowPowerModeOnBattery = true
            next.stopChargingWhenSleeping = false
        case .balanced:
            next.limitPercent = ProfilePresetConstants.balancedLimit
            next.sailingModeEnabled = true
            next.sailingDeltaPercent = ProfilePresetConstants.balancedSailingDelta
            next.automaticDischarge = false
            next.dischargeInClamshell = false
            next.heatProtectionEnabled = true
            next.maxTemperatureCelsius = ProfilePresetConstants.balancedMaxTemp
            next.lowPowerModeOnBattery = false
            next.stopChargingWhenSleeping = true
        case .deskDocked:
            next.limitPercent = ProfilePresetConstants.deskDockedLimit
            next.sailingModeEnabled = true
            next.sailingDeltaPercent = ProfilePresetConstants.deskDockedSailingDelta
            next.automaticDischarge = true
            next.dischargeInClamshell = true
            next.heatProtectionEnabled = true
            next.maxTemperatureCelsius = ProfilePresetConstants.deskDockedMaxTemp
            next.lowPowerModeOnBattery = false
            next.stopChargingWhenSleeping = true
        case .maxLifespan:
            next.limitPercent = ProfilePresetConstants.maxLifespanLimit
            next.sailingModeEnabled = true
            next.sailingDeltaPercent = ProfilePresetConstants.maxLifespanSailingDelta
            next.automaticDischarge = true
            next.dischargeInClamshell = true
            next.heatProtectionEnabled = true
            next.maxTemperatureCelsius = ProfilePresetConstants.maxLifespanMaxTemp
            next.lowPowerModeOnBattery = true
            next.stopChargingWhenSleeping = true
        }
        return next
    }
}
