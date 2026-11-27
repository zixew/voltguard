import Foundation

public enum VoltGuardLimits {
    public static let minLimitPercent = 20
    public static let maxLimitPercent = 100
    public static let defaultLimitPercent = 80
    public static let quickPresets = [60, 80, 90, 100]

    public static let minSailingDeltaPercent = 2
    public static let maxSailingDeltaPercent = 20
    public static let defaultSailingDeltaPercent = 5

    public static let minTemperatureCelsius = 28.0
    public static let maxTemperatureCelsius = 45.0
    public static let defaultMaxTemperatureCelsius = 35.0
    public static let heatHysteresisCelsius = 2.0

    public static let autoDischargeBufferPercent = 2
    public static let minSafeDischargePercent = 10
    public static let minSailingFloorPercent = 15

    public static let calibrationLowPercent = 15
    public static let calibrationHoldSeconds: TimeInterval = 3600

    public static let minCornerRadius = 6.0
    public static let maxCornerRadius = 18.0
    public static let defaultCornerRadius = 12.0

    public static let minSurfaceOpacity = 0.72
    public static let maxSurfaceOpacity = 1.0
    public static let defaultSurfaceOpacity = 0.94

    public static let etaEmaAlpha = 0.25
    public static let etaTimeConstantSeconds: TimeInterval = 60.0
    public static let etaUpwardHysteresisMinutes = 3
    public static let minETACurrentAmps = 0.08
    public static let maxETAMinutes = 2400

    public static let lowBatteryAlertThresholdPercent = 20
    public static let defaultDesignCycleCount = 1000
    public static let healthFairThresholdPercent = 85
    public static let healthServiceThresholdPercent = 80
}

public enum SMCKeyConstants {
    public static let chargeLimit = "BCLM"
    public static let dischargeInhibit = "CH0I"
    public static let chargeInhibitB = "CH0B"
    public static let chargeInhibitC = "CH0C"
    public static let magSafeLED = "ACLC"
}

public enum ProfilePresetConstants {
    public static let travelLimit = 100
    public static let travelMaxTemp = 36.0

    public static let balancedLimit = 80
    public static let balancedSailingDelta = 5
    public static let balancedMaxTemp = 35.0

    public static let deskDockedLimit = 75
    public static let deskDockedSailingDelta = 5
    public static let deskDockedMaxTemp = 34.0

    public static let maxLifespanLimit = 60
    public static let maxLifespanSailingDelta = 8
    public static let maxLifespanMaxTemp = 32.0

    public static let lowBatteryTravelThreshold = 30
}
