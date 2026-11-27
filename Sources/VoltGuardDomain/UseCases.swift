import Foundation

public struct PolicyEvaluationContext: Equatable, Sendable {
    public var isSailingPaused: Bool
    public var isHeatPaused: Bool
    public var isSystemSleeping: Bool

    public init(
        isSailingPaused: Bool = false,
        isHeatPaused: Bool = false,
        isSystemSleeping: Bool = false
    ) {
        self.isSailingPaused = isSailingPaused
        self.isHeatPaused = isHeatPaused
        self.isSystemSleeping = isSystemSleeping
    }
}

public struct PolicyEvaluationResult: Equatable, Sendable {
    public let command: SMCCommandState
    public let updatedPolicy: ChargePolicy
    public let updatedContext: PolicyEvaluationContext

    public init(
        command: SMCCommandState,
        updatedPolicy: ChargePolicy,
        updatedContext: PolicyEvaluationContext
    ) {
        self.command = command
        self.updatedPolicy = updatedPolicy
        self.updatedContext = updatedContext
    }
}

public struct EvaluateChargePolicyUseCase: Sendable {
    public init() {}

    public func execute(
        telemetry: BatteryTelemetry,
        policy: ChargePolicy,
        calibration: CalibrationSession,
        context: PolicyEvaluationContext
    ) -> PolicyEvaluationResult {
        var nextPolicy = policy
        var nextContext = context

        let lowPowerEnabled = policy.lowPowerModeAlways || (policy.lowPowerModeOnBattery && !telemetry.isPluggedIn)

        if context.isSystemSleeping && policy.stopChargingWhenSleeping {
            let cmd = SMCCommandState(
                targetLimitPercent: policy.limitPercent,
                allowCharging: false,
                forceDischarge: false,
                preventSleepAssertion: false,
                magSafeLED: resolvedLED(policy.magSafeLEDMode, allowCharging: false, forceDischarge: false),
                lowPowerModeEnabled: lowPowerEnabled,
                statusReason: .sleepingInhibited
            )
            return PolicyEvaluationResult(command: cmd, updatedPolicy: nextPolicy, updatedContext: nextContext)
        }

        // Calibration overrides normal limit and sailing rules.
        if calibration.isActive {
            let allowCharge = calibration.stage == .chargingToFull || calibration.stage == .holdingFull || calibration.stage == .restoringLimit
            let forceDischarge = calibration.stage == .dischargingToLow
            let limit = calibration.stage == .restoringLimit ? policy.limitPercent : 100
            let preventSleep = policy.sleepControlEnabled && (forceDischarge || calibration.stage == .chargingToFull)
            let cmd = SMCCommandState(
                targetLimitPercent: limit,
                allowCharging: allowCharge,
                forceDischarge: forceDischarge,
                preventSleepAssertion: preventSleep,
                magSafeLED: resolvedLED(policy.magSafeLEDMode, allowCharging: allowCharge, forceDischarge: forceDischarge),
                lowPowerModeEnabled: lowPowerEnabled,
                statusReason: .calibrationActive
            )
            return PolicyEvaluationResult(command: cmd, updatedPolicy: nextPolicy, updatedContext: nextContext)
        }

        // Top Up reverts automatically once battery hits 100%.
        if nextPolicy.topUpActive && telemetry.percentage >= 100 {
            nextPolicy.topUpActive = false
        }

        let effectiveLimit = nextPolicy.topUpActive ? 100 : nextPolicy.limitPercent

        // Heat protection uses a hysteresis band to avoid rapid toggling.
        if nextPolicy.heatProtectionEnabled {
            if telemetry.temperatureCelsius >= nextPolicy.maxTemperatureCelsius {
                nextContext.isHeatPaused = true
            } else if telemetry.temperatureCelsius <= nextPolicy.maxTemperatureCelsius - VoltGuardLimits.heatHysteresisCelsius {
                nextContext.isHeatPaused = false
            }
        } else {
            nextContext.isHeatPaused = false
        }

        if nextContext.isHeatPaused {
            let cmd = SMCCommandState(
                targetLimitPercent: effectiveLimit,
                allowCharging: false,
                forceDischarge: false,
                preventSleepAssertion: false,
                magSafeLED: resolvedLED(nextPolicy.magSafeLEDMode, allowCharging: false, forceDischarge: false),
                lowPowerModeEnabled: lowPowerEnabled,
                statusReason: .heatProtectionPaused
            )
            return PolicyEvaluationResult(command: cmd, updatedPolicy: nextPolicy, updatedContext: nextContext)
        }

        let canDischargeInCurrentLidState = !telemetry.isClamshellClosed || nextPolicy.dischargeInClamshell

        if nextPolicy.manualDischarge && telemetry.isPluggedIn && canDischargeInCurrentLidState && telemetry.percentage > VoltGuardLimits.minSafeDischargePercent {
            let cmd = SMCCommandState(
                targetLimitPercent: effectiveLimit,
                allowCharging: false,
                forceDischarge: true,
                preventSleepAssertion: nextPolicy.sleepControlEnabled,
                magSafeLED: resolvedLED(nextPolicy.magSafeLEDMode, allowCharging: false, forceDischarge: true),
                lowPowerModeEnabled: lowPowerEnabled,
                statusReason: .manualDischarge
            )
            return PolicyEvaluationResult(command: cmd, updatedPolicy: nextPolicy, updatedContext: nextContext)
        }

        if nextPolicy.automaticDischarge && telemetry.isPluggedIn && canDischargeInCurrentLidState && telemetry.percentage > effectiveLimit + VoltGuardLimits.autoDischargeBufferPercent {
            let cmd = SMCCommandState(
                targetLimitPercent: effectiveLimit,
                allowCharging: false,
                forceDischarge: true,
                preventSleepAssertion: nextPolicy.sleepControlEnabled,
                magSafeLED: resolvedLED(nextPolicy.magSafeLEDMode, allowCharging: false, forceDischarge: true),
                lowPowerModeEnabled: lowPowerEnabled,
                statusReason: .automaticDischarge
            )
            return PolicyEvaluationResult(command: cmd, updatedPolicy: nextPolicy, updatedContext: nextContext)
        }

        if nextPolicy.sailingModeEnabled && !nextPolicy.topUpActive {
            let lowerBound = max(effectiveLimit - nextPolicy.sailingDeltaPercent, VoltGuardLimits.minSailingFloorPercent)
            if telemetry.percentage >= effectiveLimit {
                nextContext.isSailingPaused = true
            } else if telemetry.percentage <= lowerBound {
                nextContext.isSailingPaused = false
            }
            if nextContext.isSailingPaused {
                let cmd = SMCCommandState(
                    targetLimitPercent: effectiveLimit,
                    allowCharging: false,
                    forceDischarge: false,
                    preventSleepAssertion: false,
                    magSafeLED: resolvedLED(nextPolicy.magSafeLEDMode, allowCharging: false, forceDischarge: false),
                    lowPowerModeEnabled: lowPowerEnabled,
                    statusReason: .sailingPaused
                )
                return PolicyEvaluationResult(command: cmd, updatedPolicy: nextPolicy, updatedContext: nextContext)
            }
        } else {
            nextContext.isSailingPaused = false
        }

        let allowCharge = telemetry.percentage < effectiveLimit
        let reason: PolicyReason = nextPolicy.topUpActive ? .topUpActive : (allowCharge ? .normalCharging : .limitReached)
        let cmd = SMCCommandState(
            targetLimitPercent: effectiveLimit,
            allowCharging: allowCharge,
            forceDischarge: false,
            preventSleepAssertion: false,
            magSafeLED: resolvedLED(nextPolicy.magSafeLEDMode, allowCharging: allowCharge, forceDischarge: false),
            lowPowerModeEnabled: lowPowerEnabled,
            statusReason: reason
        )
        return PolicyEvaluationResult(command: cmd, updatedPolicy: nextPolicy, updatedContext: nextContext)
    }

    private func resolvedLED(_ mode: MagSafeLEDMode, allowCharging: Bool, forceDischarge: Bool) -> MagSafeLEDMode {
        guard mode == .syncWithLimit else { return mode }
        if forceDischarge { return .off }
        return allowCharging ? .amber : .green
    }
}

public struct CalibrationMachineUseCase: Sendable {
    public init() {}

    public func advance(
        session: CalibrationSession,
        telemetry: BatteryTelemetry,
        targetLimit: Int,
        now: Date = Date()
    ) -> CalibrationSession {
        var next = session
        switch session.stage {
        case .idle, .completed:
            return next
        case .chargingToFull:
            if telemetry.percentage >= 100 {
                next.stage = .holdingFull
                next.stageStartedAt = now
            }
        case .holdingFull:
            if let started = session.stageStartedAt, now.timeIntervalSince(started) >= session.holdDurationSeconds {
                next.stage = .dischargingToLow
                next.stageStartedAt = now
            }
        case .dischargingToLow:
            if telemetry.percentage <= session.targetLowPercent {
                next.stage = .holdingLow
                next.stageStartedAt = now
            }
        case .holdingLow:
            if let started = session.stageStartedAt, now.timeIntervalSince(started) >= session.holdDurationSeconds {
                next.stage = .restoringLimit
                next.stageStartedAt = now
            }
        case .restoringLimit:
            if telemetry.percentage >= targetLimit {
                next.stage = .completed
                next.stageStartedAt = now
            }
        }
        return next
    }
}

public struct ScheduleEvaluatorUseCase: Sendable {
    public init() {}

    public func matchingActions(
        rules: [ScheduleRule],
        date: Date,
        calendar: Calendar = .current
    ) -> [ScheduleAction] {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute else {
            return []
        }
        return rules.compactMap { rule in
            guard rule.isEnabled,
                  rule.weekdays.contains(weekday),
                  rule.hour == hour,
                  rule.minute == minute else {
                return nil
            }
            return rule.action
        }
    }
}

public struct PowerFlowCalculator: Sendable {
    public init() {}

    public func calculate(from telemetry: BatteryTelemetry) -> PowerFlowMetrics {
        let batteryWatts = telemetry.voltageVolts * telemetry.amperageAmps
        if !telemetry.isPluggedIn {
            let systemDraw = abs(min(batteryWatts, 0))
            return PowerFlowMetrics(adapterInputWatts: 0, batteryNetWatts: batteryWatts, systemLoadWatts: systemDraw)
        }
        let adapterIn = max(telemetry.adapterWatts, max(batteryWatts, 0))
        let systemLoad = max(adapterIn - batteryWatts, 0)
        return PowerFlowMetrics(
            adapterInputWatts: adapterIn,
            batteryNetWatts: batteryWatts,
            systemLoadWatts: systemLoad
        )
    }
}

public enum ETAKind: Equatable, Sendable {
    case toEmpty
    case toTargetLimit
    case steady
}

public struct BatteryETA: Equatable, Sendable {
    public let kind: ETAKind
    public let minutes: Int?
    public let targetPercent: Int

    public init(kind: ETAKind, minutes: Int?, targetPercent: Int) {
        self.kind = kind
        self.minutes = minutes
        self.targetPercent = targetPercent
    }
}

public struct BatteryETACalculator: Sendable {
    private var smoothedAmps: Double?
    private var lastTimestamp: Date?
    private var lastIsPluggedIn: Bool?
    private var lastIsCharging: Bool?
    private var lastKind: ETAKind?
    private var lastTargetPercent: Int?
    private var lastDisplayedMinutes: Int?

    public init() {}

    public mutating func update(telemetry: BatteryTelemetry, targetLimit: Int) -> BatteryETA {
        let dt: TimeInterval
        if let prevTs = lastTimestamp {
            let rawDt = telemetry.timestamp.timeIntervalSince(prevTs)
            dt = rawDt > 0 ? min(max(rawDt, 0.5), 300.0) : 2.0
        } else {
            dt = 2.0
        }
        lastTimestamp = telemetry.timestamp

        let plugOrChargeChanged = (lastIsPluggedIn != nil && lastIsPluggedIn != telemetry.isPluggedIn)
            || (lastIsCharging != nil && lastIsCharging != telemetry.isCharging)
        lastIsPluggedIn = telemetry.isPluggedIn
        lastIsCharging = telemetry.isCharging

        let currentMah = Double(
            telemetry.currentCapacityMah
            ?? Int(Double(telemetry.maxCapacityMah) * (Double(telemetry.percentage) / 100.0))
        )
        let currentAmps = telemetry.amperageAmps
        let alpha = 1.0 - exp(-dt / VoltGuardLimits.etaTimeConstantSeconds)

        if !plugOrChargeChanged, let prev = smoothedAmps, (prev >= 0) == (currentAmps >= 0) {
            smoothedAmps = prev * (1.0 - alpha) + currentAmps * alpha
        } else {
            // Seed initial battery discharge EMA from macOS AvgTimeToEmpty when available.
            if !telemetry.isPluggedIn, let mins = telemetry.timeRemainingMinutes, mins > 0, currentMah > 0 {
                let seededAmps = -((currentMah / 1000.0) / (Double(mins) / 60.0))
                smoothedAmps = (seededAmps * 0.7) + (currentAmps * 0.3)
            } else {
                smoothedAmps = currentAmps
            }
            lastDisplayedMinutes = nil
        }

        let ema = smoothedAmps ?? currentAmps
        let isActivelyCharging = telemetry.isCharging || (telemetry.isPluggedIn && ema > VoltGuardLimits.minETACurrentAmps)

        let rawETA: BatteryETA
        if isActivelyCharging {
            let effectiveTarget = telemetry.percentage >= targetLimit ? VoltGuardLimits.maxLimitPercent : targetLimit
            if telemetry.percentage >= effectiveTarget {
                rawETA = BatteryETA(kind: .steady, minutes: nil, targetPercent: effectiveTarget)
            } else if ema > VoltGuardLimits.minETACurrentAmps {
                let targetMah = Double(telemetry.maxCapacityMah) * (Double(effectiveTarget) / 100.0)
                let neededMah = max(targetMah - currentMah, 0)
                let rawMinutes = Int(((neededMah / 1000.0) / ema) * 60.0)
                let clamped = min(max(rawMinutes, 1), VoltGuardLimits.maxETAMinutes)
                rawETA = BatteryETA(kind: .toTargetLimit, minutes: clamped, targetPercent: effectiveTarget)
            } else if let sysMins = telemetry.timeRemainingMinutes, sysMins > 0 {
                let remainingToFull = max(100 - telemetry.percentage, 1)
                let remainingToTarget = max(effectiveTarget - telemetry.percentage, 1)
                let scaled = Int((Double(sysMins) * Double(remainingToTarget) / Double(remainingToFull)).rounded())
                let clamped = min(max(scaled, 1), VoltGuardLimits.maxETAMinutes)
                rawETA = BatteryETA(kind: .toTargetLimit, minutes: clamped, targetPercent: effectiveTarget)
            } else {
                rawETA = BatteryETA(kind: .toTargetLimit, minutes: nil, targetPercent: effectiveTarget)
            }
        } else if !telemetry.isPluggedIn || ema < -VoltGuardLimits.minETACurrentAmps {
            let drainAmps = abs(ema)
            if drainAmps >= VoltGuardLimits.minETACurrentAmps {
                let rawMinutes = Int(((currentMah / 1000.0) / drainAmps) * 60.0)
                let clamped = min(max(rawMinutes, 1), VoltGuardLimits.maxETAMinutes)
                rawETA = BatteryETA(kind: .toEmpty, minutes: clamped, targetPercent: 0)
            } else {
                rawETA = BatteryETA(kind: .toEmpty, minutes: telemetry.timeRemainingMinutes, targetPercent: 0)
            }
        } else {
            rawETA = BatteryETA(kind: .steady, minutes: nil, targetPercent: targetLimit)
        }

        return stabilize(rawETA, dt: dt)
    }

    private mutating func stabilize(_ eta: BatteryETA, dt: TimeInterval) -> BatteryETA {
        guard let rawMins = eta.minutes else {
            if eta.kind == .steady {
                lastKind = .steady
                lastTargetPercent = eta.targetPercent
                lastDisplayedMinutes = nil
            }
            return eta
        }
        guard lastKind == eta.kind,
              lastTargetPercent == eta.targetPercent,
              let prevMins = lastDisplayedMinutes else {
            lastKind = eta.kind
            lastTargetPercent = eta.targetPercent
            lastDisplayedMinutes = rawMins
            return eta
        }
        let maxStep = max(1, Int(dt / 15.0))
        let nextMins: Int
        if rawMins > prevMins {
            // Suppress 1-2 minute upward flicker caused by brief load dips.
            if rawMins - prevMins < VoltGuardLimits.etaUpwardHysteresisMinutes {
                nextMins = prevMins
            } else {
                nextMins = min(rawMins, prevMins + maxStep)
            }
        } else if rawMins < prevMins {
            nextMins = max(rawMins, prevMins - maxStep)
        } else {
            nextMins = prevMins
        }
        lastDisplayedMinutes = nextMins
        return BatteryETA(kind: eta.kind, minutes: nextMins, targetPercent: eta.targetPercent)
    }
}
