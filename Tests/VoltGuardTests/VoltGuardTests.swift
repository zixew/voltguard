import AppKit
import SwiftUI
import XCTest
@testable import VoltGuardDomain
@testable import VoltGuardData
@testable import VoltGuardApp

final class VoltGuardTests: XCTestCase {
    private func sampleTelemetry(
        pct: Int = 75,
        isCharging: Bool = true,
        isPluggedIn: Bool = true,
        temp: Double = 30.0,
        voltage: Double = 12.6,
        amperage: Double = 2.0,
        adapterWatts: Double = 67.0,
        clamshell: Bool = false
    ) -> BatteryTelemetry {
        BatteryTelemetry(
            percentage: pct,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            temperatureCelsius: temp,
            voltageVolts: voltage,
            amperageAmps: amperage,
            adapterWatts: adapterWatts,
            cycleCount: 42,
            maxCapacityMah: 4800,
            designCapacityMah: 5000,
            isClamshellClosed: clamshell
        )
    }

    func testChargeLimiterAndSailingHysteresis() {
        let useCase = EvaluateChargePolicyUseCase()
        var policy = ChargePolicy(limitPercent: 80, sailingModeEnabled: true, sailingDeltaPercent: 5)
        var ctx = PolicyEvaluationContext()

        let hitLimit = useCase.execute(
            telemetry: sampleTelemetry(pct: 80),
            policy: policy,
            calibration: CalibrationSession(),
            context: ctx
        )
        XCTAssertFalse(hitLimit.command.allowCharging)
        XCTAssertEqual(hitLimit.command.statusReason, .sailingPaused)
        ctx = hitLimit.updatedContext

        let stillSailing = useCase.execute(
            telemetry: sampleTelemetry(pct: 77),
            policy: policy,
            calibration: CalibrationSession(),
            context: ctx
        )
        XCTAssertFalse(stillSailing.command.allowCharging)
        ctx = stillSailing.updatedContext

        let resumed = useCase.execute(
            telemetry: sampleTelemetry(pct: 75),
            policy: policy,
            calibration: CalibrationSession(),
            context: ctx
        )
        XCTAssertTrue(resumed.command.allowCharging)
        XCTAssertEqual(resumed.command.statusReason, .normalCharging)

        policy.sailingModeEnabled = false
        let normalLimit = useCase.execute(
            telemetry: sampleTelemetry(pct: 80),
            policy: policy,
            calibration: CalibrationSession(),
            context: PolicyEvaluationContext()
        )
        XCTAssertFalse(normalLimit.command.allowCharging)
        XCTAssertEqual(normalLimit.command.statusReason, .limitReached)
    }

    func testHeatProtectionHysteresis() {
        let useCase = EvaluateChargePolicyUseCase()
        let policy = ChargePolicy(limitPercent: 80, heatProtectionEnabled: true, maxTemperatureCelsius: 35.0)
        var ctx = PolicyEvaluationContext()

        let hot = useCase.execute(
            telemetry: sampleTelemetry(pct: 50, temp: 36.0),
            policy: policy,
            calibration: CalibrationSession(),
            context: ctx
        )
        XCTAssertFalse(hot.command.allowCharging)
        XCTAssertEqual(hot.command.statusReason, .heatProtectionPaused)
        ctx = hot.updatedContext

        let stillWarm = useCase.execute(
            telemetry: sampleTelemetry(pct: 50, temp: 34.0),
            policy: policy,
            calibration: CalibrationSession(),
            context: ctx
        )
        XCTAssertFalse(stillWarm.command.allowCharging)
        ctx = stillWarm.updatedContext

        let cooled = useCase.execute(
            telemetry: sampleTelemetry(pct: 50, temp: 32.5),
            policy: policy,
            calibration: CalibrationSession(),
            context: ctx
        )
        XCTAssertTrue(cooled.command.allowCharging)
        XCTAssertEqual(cooled.command.statusReason, .normalCharging)
    }

    func testDischargeAndClamshellMode() {
        let useCase = EvaluateChargePolicyUseCase()
        var policy = ChargePolicy(limitPercent: 80, manualDischarge: true, dischargeInClamshell: false)

        let blockedInClamshell = useCase.execute(
            telemetry: sampleTelemetry(pct: 70, clamshell: true),
            policy: policy,
            calibration: CalibrationSession(),
            context: PolicyEvaluationContext()
        )
        XCTAssertFalse(blockedInClamshell.command.forceDischarge)

        policy.dischargeInClamshell = true
        let allowedInClamshell = useCase.execute(
            telemetry: sampleTelemetry(pct: 70, clamshell: true),
            policy: policy,
            calibration: CalibrationSession(),
            context: PolicyEvaluationContext()
        )
        XCTAssertTrue(allowedInClamshell.command.forceDischarge)
        XCTAssertEqual(allowedInClamshell.command.statusReason, .manualDischarge)
        XCTAssertEqual(allowedInClamshell.command.magSafeLED, .off)
    }

    func testTopUpRevertsAtFull() {
        let useCase = EvaluateChargePolicyUseCase()
        let policy = ChargePolicy(limitPercent: 80, topUpActive: true)

        let topping = useCase.execute(
            telemetry: sampleTelemetry(pct: 90),
            policy: policy,
            calibration: CalibrationSession(),
            context: PolicyEvaluationContext()
        )
        XCTAssertTrue(topping.command.allowCharging)
        XCTAssertEqual(topping.command.targetLimitPercent, 100)
        XCTAssertTrue(topping.updatedPolicy.topUpActive)

        let full = useCase.execute(
            telemetry: sampleTelemetry(pct: 100),
            policy: policy,
            calibration: CalibrationSession(),
            context: PolicyEvaluationContext()
        )
        XCTAssertFalse(full.updatedPolicy.topUpActive)
        XCTAssertFalse(full.command.allowCharging)
    }

    func testSleepInhibitStopsCharging() {
        let useCase = EvaluateChargePolicyUseCase()
        let policy = ChargePolicy(limitPercent: 80, stopChargingWhenSleeping: true)
        let ctx = PolicyEvaluationContext(isSystemSleeping: true)

        let res = useCase.execute(
            telemetry: sampleTelemetry(pct: 40),
            policy: policy,
            calibration: CalibrationSession(),
            context: ctx
        )
        XCTAssertFalse(res.command.allowCharging)
        XCTAssertEqual(res.command.statusReason, .sleepingInhibited)
    }

    func testCalibrationStages() {
        let machine = CalibrationMachineUseCase()
        let policyUseCase = EvaluateChargePolicyUseCase()
        let policy = ChargePolicy(limitPercent: 80, sleepControlEnabled: true)
        let start = Date(timeIntervalSince1970: 1000)
        var session = CalibrationSession(stage: .chargingToFull, stageStartedAt: start, targetLowPercent: 15, holdDurationSeconds: 60)

        let stage1Eval = policyUseCase.execute(telemetry: sampleTelemetry(pct: 90), policy: policy, calibration: session, context: PolicyEvaluationContext())
        XCTAssertTrue(stage1Eval.command.allowCharging)
        XCTAssertFalse(stage1Eval.command.forceDischarge)
        XCTAssertTrue(stage1Eval.command.preventSleepAssertion)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 100), targetLimit: 80, now: start.addingTimeInterval(10))
        XCTAssertEqual(session.stage, .holdingFull)
        let stage2Eval = policyUseCase.execute(telemetry: sampleTelemetry(pct: 100), policy: policy, calibration: session, context: PolicyEvaluationContext())
        XCTAssertTrue(stage2Eval.command.allowCharging)
        XCTAssertFalse(stage2Eval.command.forceDischarge)
        XCTAssertTrue(stage2Eval.command.preventSleepAssertion)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 100), targetLimit: 80, now: start.addingTimeInterval(80))
        XCTAssertEqual(session.stage, .dischargingToLow)
        let stage3Eval = policyUseCase.execute(telemetry: sampleTelemetry(pct: 50), policy: policy, calibration: session, context: PolicyEvaluationContext())
        XCTAssertFalse(stage3Eval.command.allowCharging)
        XCTAssertTrue(stage3Eval.command.forceDischarge)
        XCTAssertTrue(stage3Eval.command.preventSleepAssertion)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 15), targetLimit: 80, now: start.addingTimeInterval(200))
        XCTAssertEqual(session.stage, .holdingLow)
        let stage4Eval = policyUseCase.execute(telemetry: sampleTelemetry(pct: 15), policy: policy, calibration: session, context: PolicyEvaluationContext())
        XCTAssertFalse(stage4Eval.command.allowCharging)
        XCTAssertFalse(stage4Eval.command.forceDischarge)
        XCTAssertTrue(stage4Eval.command.preventSleepAssertion)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 15), targetLimit: 80, now: start.addingTimeInterval(270))
        XCTAssertEqual(session.stage, .restoringLimit)
        let stage5Eval = policyUseCase.execute(telemetry: sampleTelemetry(pct: 40), policy: policy, calibration: session, context: PolicyEvaluationContext())
        XCTAssertTrue(stage5Eval.command.allowCharging)
        XCTAssertFalse(stage5Eval.command.forceDischarge)
        XCTAssertEqual(stage5Eval.command.targetLimitPercent, 80)
        XCTAssertTrue(stage5Eval.command.preventSleepAssertion)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 80), targetLimit: 80, now: start.addingTimeInterval(400))
        XCTAssertEqual(session.stage, .completed)
    }

    func testScheduleEvaluator() {
        let evaluator = ScheduleEvaluatorUseCase()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_000_000) // Tue Nov 14 2023 22:13:20 GMT
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: date)

        let rule = ScheduleRule(
            title: "Morning Top Up",
            hour: comps.hour!,
            minute: comps.minute!,
            weekdays: [comps.weekday!],
            action: .topUp100
        )
        let actions = evaluator.matchingActions(rules: [rule], date: date, calendar: cal)
        XCTAssertEqual(actions, [.topUp100])
    }

    func testPowerFlowCalculator() {
        let calc = PowerFlowCalculator()
        let charging = sampleTelemetry(isCharging: true, isPluggedIn: true, voltage: 12.0, amperage: 3.0, adapterWatts: 67.0)
        let flow = calc.calculate(from: charging)
        XCTAssertEqual(flow.adapterInputWatts, 67.0, accuracy: 0.01)
        XCTAssertEqual(flow.batteryNetWatts, 36.0, accuracy: 0.01)
        XCTAssertEqual(flow.systemLoadWatts, 31.0, accuracy: 0.01)
    }

    func testBatteryReaderParse() {
        let props: [String: Any] = [
            "CurrentCapacity": 72,
            "MaxCapacity": 100,
            "NominalChargeCapacity": 4750,
            "DesignCapacity": 5000,
            "IsCharging": true,
            "ExternalConnected": true,
            "Temperature": 3051,
            "Voltage": 12450,
            "Amperage": 1800,
            "CycleCount": 55,
            "AdapterDetails": ["Watts": 67]
        ]
        let t = IOKitBatteryReader.parseRegistryProperties(props, isClamshellClosed: false)
        XCTAssertEqual(t.percentage, 72)
        XCTAssertEqual(t.healthPercent, 95)
        XCTAssertEqual(t.temperatureCelsius, 31.95, accuracy: 0.05)
        XCTAssertEqual(t.adapterWatts, 67.0, accuracy: 0.01)
    }

    func testLocalizationCompletenessAndNoEmDash() {
        for key in L10nKey.allCases {
            let enStr = L10n.en[key]
            let idStr = L10n.id[key]
            XCTAssertNotNil(enStr, "Missing EN key: \(key)")
            XCTAssertNotNil(idStr, "Missing ID key: \(key)")
            XCTAssertFalse(enStr?.contains("—") ?? false, "Em dash in EN key: \(key)")
            XCTAssertFalse(idStr?.contains("—") ?? false, "Em dash in ID key: \(key)")
        }
    }

    @MainActor
    func testPresenterWeakDeallocationNoMemoryLeak() {
        weak var weakPresenter: VoltGuardPresenter?
        autoreleasepool {
            let interactor = makeIsolatedInteractor()
            let presenter = VoltGuardPresenter(interactor: interactor)
            weakPresenter = presenter
            XCTAssertNotNil(weakPresenter)
        }
        XCTAssertNil(weakPresenter, "VoltGuardPresenter should deallocate cleanly without retain cycles")
    }

    func testConstantsIntegrity() {
        XCTAssertEqual(VoltGuardLimits.minLimitPercent, 20)
        XCTAssertEqual(VoltGuardLimits.maxLimitPercent, 100)
        XCTAssertEqual(VoltGuardLimits.defaultLimitPercent, 80)
        XCTAssertEqual(AppLayoutConstants.popoverWidth, 340)
        XCTAssertTrue(ThemeHexConstants.obsidianSlate.accent.hasPrefix("#"))
        XCTAssertGreaterThan(MotionConstants.ringSpringResponse, 0)
        XCTAssertGreaterThan(MotionConstants.flowCycleSeconds, 0)
    }

    func testEnergyMonitorParsingAndImpactLevels() {
        let sample = """
          101  42.5 /Applications/Xcode.app/Contents/MacOS/Xcode
          202  11.0 /Applications/Safari.app/Contents/MacOS/Safari
          303   2.1 /Applications/Notes.app/Contents/MacOS/Notes
          404  99.0 /Applications/VoltGuard.app/Contents/MacOS/VoltGuard
        """
        let meta: [Int32: (String, String?)] = [
            101: ("Xcode", "com.apple.dt.Xcode"),
            202: ("Safari", "com.apple.Safari"),
            303: ("Notes", "com.apple.Notes"),
            404: ("VoltGuard", "com.voltguard.app")
        ]
        let parsed = SystemEnergyMonitor.parsePSOutput(sample, runningAppMetadata: meta, excludedPID: 404, limit: 10)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].name, "Xcode")
        XCTAssertEqual(parsed[0].impact, .high)
        XCTAssertEqual(parsed[1].impact, .medium)
        XCTAssertEqual(parsed[2].impact, .low)
    }

    @MainActor
    func testPresenterFullFeatureDispatchAndRouter() async {
        final class MockRouter: AppRouterProtocol {
            var didOpenFullApp = false
            var didMinimize = false
            var menuBarIconVisible = true
            func openFullAppWindow() { didOpenFullApp = true }
            func minimizeToBackground() { didMinimize = true }
            func setMenuBarIconVisible(_ visible: Bool) { menuBarIconVisible = visible }
        }

        let interactor = makeIsolatedInteractor()
        let presenter = VoltGuardPresenter(interactor: interactor)
        let router = MockRouter()
        presenter.router = router

        presenter.dispatch(.setChargeLimit(85))
        XCTAssertEqual(presenter.state.settings.policy.limitPercent, 85)

        presenter.dispatch(.toggleManualDischarge)
        XCTAssertTrue(presenter.state.settings.policy.manualDischarge)

        presenter.dispatch(.toggleTopUp)
        XCTAssertTrue(presenter.state.settings.policy.topUpActive)

        presenter.dispatch(.updateLocale(.id))
        XCTAssertEqual(presenter.state.settings.locale, .id)

        let rule = ScheduleRule(title: "Desk", hour: 9, minute: 0, action: .setLimit80)
        presenter.dispatch(.addScheduleRule(rule))
        XCTAssertEqual(presenter.state.settings.schedules.count, 1)
        presenter.dispatch(.toggleScheduleRule(rule.id))
        XCTAssertFalse(presenter.state.settings.schedules[0].isEnabled)
        presenter.dispatch(.removeScheduleRule(rule.id))
        XCTAssertTrue(presenter.state.settings.schedules.isEmpty)

        presenter.dispatch(.openFullApp)
        XCTAssertTrue(router.didOpenFullApp)

        presenter.dispatch(.minimizeToBackground)
        XCTAssertTrue(router.didMinimize)

        presenter.dispatch(.hideMenuBarIcon)
        XCTAssertFalse(router.menuBarIconVisible)

        // Verify immediate 0ms sync and immunity to stale background tick overwrite.
        presenter.dispatch(.setChargeLimit(85))
        presenter.dispatch(.toggleManualDischarge)
        XCTAssertTrue(presenter.state.settings.policy.manualDischarge)
        await interactor.tick(settings: presenter.state.settings, calibration: presenter.state.calibration, generation: 0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let staleSettings = presenter.state.settings
        presenter.dispatch(.toggleManualDischarge)
        presenter.dispatch(.setChargeLimit(60))
        XCTAssertFalse(presenter.state.settings.policy.manualDischarge)
        XCTAssertEqual(presenter.state.settings.policy.limitPercent, 60)
        await interactor.tick(settings: staleSettings, calibration: CalibrationSession(), generation: 0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(presenter.state.settings.policy.manualDischarge, "Stale background tick must not revert toolbar state change")
        XCTAssertEqual(presenter.state.settings.policy.limitPercent, 60)
    }

    func testRecommendProfileUseCaseAllConditions() {
        let recommender = RecommendProfileUseCase()
        let base = ChargePolicy()

        let hot = recommender.recommend(telemetry: sampleTelemetry(isPluggedIn: true, temp: 36.5), currentPolicy: base)
        XCTAssertEqual(hot.tier, .maxLifespan)
        XCTAssertEqual(hot.reason, .highTemperature)

        let clamshell = recommender.recommend(telemetry: sampleTelemetry(isPluggedIn: true, temp: 30.0, clamshell: true), currentPolicy: base)
        XCTAssertEqual(clamshell.tier, .deskDocked)
        XCTAssertEqual(clamshell.reason, .clamshellDocked)

        let lowMob = recommender.recommend(telemetry: sampleTelemetry(pct: 25, isCharging: false, isPluggedIn: false, temp: 29.0), currentPolicy: base)
        XCTAssertEqual(lowMob.tier, .travel)
        XCTAssertEqual(lowMob.reason, .lowBatteryUnplugged)

        let daily = recommender.recommend(telemetry: sampleTelemetry(pct: 70, isPluggedIn: true, temp: 29.0), currentPolicy: base)
        XCTAssertEqual(daily.tier, .balanced)
        XCTAssertEqual(daily.reason, .dailyBalanced)
        XCTAssertFalse(daily.isAlreadyApplied)

        let appliedPolicy = recommender.policy(for: .balanced, preserving: base)
        let afterApply = recommender.recommend(telemetry: sampleTelemetry(pct: 70, isPluggedIn: true, temp: 29.0), currentPolicy: appliedPolicy)
        XCTAssertTrue(afterApply.isAlreadyApplied)
    }

    func testSingleInstanceGuardBlocksSecondAcquire() {
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("voltguard-lock-\(UUID().uuidString).lock")
        let first = SingleInstanceGuard(lockFileURL: lockURL)
        let second = SingleInstanceGuard(lockFileURL: lockURL)

        XCTAssertTrue(first.acquireLock())
        XCTAssertFalse(second.acquireLock(), "Second instance must not acquire lock while first holds it")

        first.releaseLock()
        XCTAssertTrue(second.acquireLock(), "Second instance should acquire lock after first releases it")
        second.releaseLock()
        try? FileManager.default.removeItem(at: lockURL)
    }

    @MainActor
    func testTelemetryHistoryBufferCappedAtMaxSamples() {
        var history: [TelemetrySample] = []
        for idx in 1...45 {
            history = VoltGuardPresenter.appendSample(
                TelemetrySample(watts: Double(idx), temperatureCelsius: 30.0),
                to: history
            )
        }
        XCTAssertEqual(history.count, LiquidBatteryConstants.sparklineMaxSamples)
        XCTAssertEqual(history.first?.watts, 16.0)
        XCTAssertEqual(history.last?.watts, 45.0)
    }

    func testSmartAlertsFireOnEdgeTransitionsOnly() async {
        final class MockBatteryReader: BatteryReadingGateway, @unchecked Sendable {
            var temp: Double = 36.5
            var pct: Int = 60
            var plugged: Bool = true
            func readTelemetry() throws -> BatteryTelemetry {
                BatteryTelemetry(
                    percentage: pct,
                    isCharging: pct < 80,
                    isPluggedIn: plugged,
                    temperatureCelsius: temp,
                    voltageVolts: 12.5,
                    amperageAmps: 1.5,
                    adapterWatts: 67,
                    cycleCount: 10,
                    maxCapacityMah: 4900,
                    designCapacityMah: 5000
                )
            }
        }
        final class MockSMC: SMCControlGateway, @unchecked Sendable {
            var isPrivilegedHelperConnected: Bool { false }
            func applyCommand(_ command: SMCCommandState) async throws {}
            func installHelper() async throws {}
            func uninstallHelper() async throws {}
        }
        final class MockPower: PowerManagementGateway, @unchecked Sendable {
            func setPreventSleep(_ prevent: Bool, reason: String) {}
            func setLowPowerMode(_ enabled: Bool) async {}
        }
        final class MockAlerts: AlertNotificationGateway, @unchecked Sendable {
            var sentIDs: [String] = []
            func requestAuthorization() {}
            func sendAlert(id: String, title: String, body: String) { sentIDs.append(id) }
        }

        let reader = MockBatteryReader()
        let alerts = MockAlerts()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("voltguard-alert-\(UUID().uuidString).json")
        let interactor = VoltGuardInteractor(
            batteryReader: reader,
            smcGateway: MockSMC(),
            powerGateway: MockPower(),
            settingsRepo: JSONSettingsRepository(fileURL: tempURL),
            alertGateway: alerts
        )
        let settings = AppSettings(alertsEnabled: true)
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        XCTAssertEqual(alerts.sentIDs, ["voltguard.heat"], "Heat alert should fire once per transition")

        // Cool down to normal charging at 79%, then hit 80% limit -> fires limitreached once.
        reader.temp = 30.0
        reader.pct = 79
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        reader.pct = 80
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        XCTAssertEqual(alerts.sentIDs, ["voltguard.heat", "voltguard.limitreached"])

        // Minor 1-2% drift (79% -> 80%) while plugged in must NOT re-spam limitreached because latch resets only below limit - 5%.
        reader.pct = 79
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        reader.pct = 80
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        XCTAssertEqual(alerts.sentIDs, ["voltguard.heat", "voltguard.limitreached"], "Limit alert must not spam on minor drift near cap")
    }

    func testHealthHistoryRepositoryAndCSVExport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voltguard-health-\(UUID().uuidString).json")
        let repo = JSONHealthHistoryRepository(fileURL: url)

        let t1 = sampleTelemetry(temp: 31.0)
        let t2 = sampleTelemetry(temp: 35.5)
        _ = repo.recordSnapshot(from: t1)
        let list = repo.recordSnapshot(from: t2)

        XCTAssertEqual(list.count, 1, "Same day should aggregate into one snapshot")
        XCTAssertEqual(list[0].peakTemperatureCelsius, 35.5, accuracy: 0.01)

        let csv = repo.exportCSV()
        XCTAssertTrue(csv.contains("date,health_percent,cycle_count,peak_temp_c"))
        XCTAssertTrue(csv.contains(",96,42,35.5"))
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func testPopoverModuleReorderAndDiagnostics() async {
        let interactor = makeIsolatedInteractor()
        let presenter = VoltGuardPresenter(interactor: interactor)

        let initialFirst = presenter.state.settings.popoverLayout.orderedModules[0]
        let initialSecond = presenter.state.settings.popoverLayout.orderedModules[1]
        presenter.dispatch(.movePopoverModule(initialFirst, 1))
        XCTAssertEqual(presenter.state.settings.popoverLayout.orderedModules[0], initialSecond)
        XCTAssertEqual(presenter.state.settings.popoverLayout.orderedModules[1], initialFirst)

        presenter.dispatch(.runDiagnostics)
        XCTAssertTrue(presenter.state.isRunningDiagnostics)
        for _ in 0..<60 where presenter.state.diagnostics == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(presenter.state.diagnostics)
    }

    func testBatteryETACalculatorToEmptyAndToLimit() {
        var calc = BatteryETACalculator()

        // 50% of 4800 mAh = 2400 mAh; draining at -1.0 A -> 144 min
        let draining = sampleTelemetry(pct: 50, isCharging: false, isPluggedIn: false, amperage: -1.0)
        let etaEmpty = calc.update(telemetry: draining, targetLimit: 80)
        XCTAssertEqual(etaEmpty.kind, .toEmpty)
        XCTAssertEqual(etaEmpty.minutes, 144)

        // 50% -> 80% of 4800 mAh = 1440 mAh needed; charging at +1.5 A -> 57.6 min -> rounded to 58 min
        let charging = sampleTelemetry(pct: 50, isCharging: true, isPluggedIn: true, amperage: 1.5)
        let etaLimit = calc.update(telemetry: charging, targetLimit: 80)
        XCTAssertEqual(etaLimit.kind, .toTargetLimit)
        XCTAssertEqual(etaLimit.minutes, 58)

        // Charging below limit with near-zero initial current -> baseline 1.2A charge fallback (1440 mAh -> 72 min)
        var lowCurrentCalc = BatteryETACalculator()
        let lowCurrent = sampleTelemetry(pct: 50, isCharging: true, isPluggedIn: true, amperage: 0.01)
        let etaCalculating = lowCurrentCalc.update(telemetry: lowCurrent, targetLimit: 80)
        XCTAssertEqual(etaCalculating.kind, .toTargetLimit)
        XCTAssertEqual(etaCalculating.minutes, 72)
        XCTAssertEqual(etaCalculating.targetPercent, 80)

        // At target limit while plugged in -> steady
        let atLimit = sampleTelemetry(pct: 80, isCharging: false, isPluggedIn: true, amperage: 0.0)
        let etaSteady = lowCurrentCalc.update(telemetry: atLimit, targetLimit: 80)
        XCTAssertEqual(etaSteady.kind, .steady)
        XCTAssertEqual(etaSteady.targetPercent, 80)

        // Formatting checks (ID & EN)
        XCTAssertEqual(BatteryETAFormatter.text(for: etaEmpty, locale: .id), "2j 24m sampai habis")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaEmpty, locale: .en), "2h 24m until empty")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaLimit, locale: .id), "58m sampai penuh 80%")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaLimit, locale: .en), "58m to 80% full")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaSteady, locale: .id), "Batas 80% (Bypass Aktif)")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaSteady, locale: .en), "80% limit (Bypass Active)")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaCalculating, locale: .id), "1j 12m sampai penuh 80%")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaCalculating, locale: .en), "1h 12m to 80% full")
        let nilETA = BatteryETA(kind: .toTargetLimit, minutes: nil, targetPercent: 80)
        XCTAssertEqual(BatteryETAFormatter.text(for: nilETA, locale: .id), "Menghitung sisa waktu...")
        XCTAssertEqual(BatteryETAFormatter.text(for: nilETA, locale: .en), "Calculating time...")
    }

    func testBatteryETACalculatorTimeAwareSmoothingAndHysteresis() {
        var calc = BatteryETACalculator()
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        // Initial discharge at -1.0 A with 2400 mAh raw capacity -> 144 min
        let base = BatteryTelemetry(
            percentage: 50,
            isCharging: false,
            isPluggedIn: false,
            temperatureCelsius: 30,
            voltageVolts: 12.0,
            amperageAmps: -1.0,
            adapterWatts: 0,
            cycleCount: 10,
            currentCapacityMah: 2400,
            maxCapacityMah: 4800,
            designCapacityMah: 5000,
            timestamp: t0
        )
        let eta0 = calc.update(telemetry: base, targetLimit: 80)
        XCTAssertEqual(eta0.minutes, 144)

        // Sudden 2-second CPU spike (-3.0 A) must be held steady by wall-clock cadence gate (no 1-2s rapid countdown!).
        let spike = BatteryTelemetry(
            percentage: 50,
            isCharging: false,
            isPluggedIn: false,
            temperatureCelsius: 30,
            voltageVolts: 12.0,
            amperageAmps: -3.0,
            adapterWatts: 0,
            cycleCount: 10,
            currentCapacityMah: 2399,
            maxCapacityMah: 4800,
            designCapacityMah: 5000,
            timestamp: t0.addingTimeInterval(2)
        )
        let etaSpike = calc.update(telemetry: spike, targetLimit: 80)
        XCTAssertEqual(etaSpike.minutes, 144, "Must not tick down within 2 seconds")

        // After 35 seconds of real wall-clock time, display is allowed to step down by 1 minute.
        let after35s = BatteryTelemetry(
            percentage: 50,
            isCharging: false,
            isPluggedIn: false,
            temperatureCelsius: 30,
            voltageVolts: 12.0,
            amperageAmps: -1.5,
            adapterWatts: 0,
            cycleCount: 10,
            currentCapacityMah: 2385,
            maxCapacityMah: 4800,
            designCapacityMah: 5000,
            timestamp: t0.addingTimeInterval(35)
        )
        let etaAfter35s = calc.update(telemetry: after35s, targetLimit: 80)
        XCTAssertEqual(etaAfter35s.minutes, 143)

        // Brief load dip (+1-2 min upward drift) is suppressed by upward hysteresis.
        var hysteresisCalc = BatteryETACalculator()
        let steady = BatteryTelemetry(
            percentage: 50,
            isCharging: false,
            isPluggedIn: false,
            temperatureCelsius: 30,
            voltageVolts: 12.0,
            amperageAmps: -1.0,
            adapterWatts: 0,
            cycleCount: 10,
            currentCapacityMah: 2400,
            maxCapacityMah: 4800,
            designCapacityMah: 5000,
            timestamp: t0
        )
        XCTAssertEqual(hysteresisCalc.update(telemetry: steady, targetLimit: 80).minutes, 144)

        let dip = BatteryTelemetry(
            percentage: 50,
            isCharging: false,
            isPluggedIn: false,
            temperatureCelsius: 30,
            voltageVolts: 12.0,
            amperageAmps: -0.5,
            adapterWatts: 0,
            cycleCount: 10,
            currentCapacityMah: 2400,
            maxCapacityMah: 4800,
            designCapacityMah: 5000,
            timestamp: t0.addingTimeInterval(2)
        )
        let etaDip = hysteresisCalc.update(telemetry: dip, targetLimit: 80)
        XCTAssertEqual(etaDip.minutes, 144)

        // Transitioning from battery drain to plugged-in charging must NEVER return .toEmpty, even if initial current is negative or percentage > targetLimit.
        let pluggedInTransition = BatteryTelemetry(
            percentage: 84,
            isCharging: true,
            isPluggedIn: true,
            temperatureCelsius: 30,
            voltageVolts: 12.6,
            amperageAmps: -0.1,
            adapterWatts: 30,
            cycleCount: 210,
            currentCapacityMah: 3461,
            maxCapacityMah: 4295,
            designCapacityMah: 4629,
            timeRemainingMinutes: 164,
            timestamp: t0.addingTimeInterval(6)
        )
        let etaTransition = hysteresisCalc.update(telemetry: pluggedInTransition, targetLimit: 80)
        XCTAssertEqual(etaTransition.kind, .toTargetLimit)
        XCTAssertEqual(etaTransition.targetPercent, 100)
        XCTAssertEqual(etaTransition.minutes, 164)
    }

    func testBatteryHealthRoundingConditionAndHardwareMetadata() {
        // Apple Silicon places NominalChargeCapacity (4291) & DesignCapacity (4629) inside BatteryData -> 92.7% rounds to 93%.
        let props: [String: Any] = [
            "CurrentCapacity": 85,
            "MaxCapacity": 100,
            "CycleCount": 210,
            "DesignCycleCount9C": 1000,
            "DeviceName": "bq40z651",
            "PermanentFailureStatus": 0,
            "IsCharging": false,
            "ExternalConnected": false,
            "Temperature": 3031.5,
            "Voltage": 12385,
            "Amperage": -1010,
            "BatteryData": [
                "AppleRawCurrentCapacity": 3354,
                "AppleRawMaxCapacity": 4164,
                "NominalChargeCapacity": 4291,
                "DesignCapacity": 4629
            ]
        ]
        let parsed = IOKitBatteryReader.parseRegistryProperties(props)
        XCTAssertEqual(parsed.healthPercent, 93)
        XCTAssertEqual(parsed.maxCapacityMah, 4291)
        XCTAssertEqual(parsed.designCapacityMah, 4629)
        XCTAssertEqual(parsed.batteryCondition, .normal)
        XCTAssertEqual(parsed.designCycleCount, 1000)
        XCTAssertEqual(parsed.deviceName, "bq40z651")
        XCTAssertEqual(parsed.currentCapacityMah, 3354)
        XCTAssertFalse(parsed.permanentFailure)

        let fair = BatteryTelemetry(
            percentage: 80,
            isCharging: false,
            isPluggedIn: false,
            temperatureCelsius: 30,
            voltageVolts: 12.0,
            amperageAmps: -1.0,
            adapterWatts: 0,
            cycleCount: 400,
            maxCapacityMah: 4100,
            designCapacityMah: 5000
        )
        XCTAssertEqual(fair.healthPercent, 82)
        XCTAssertEqual(fair.batteryCondition, .fair)

        let degraded = BatteryTelemetry(
            percentage: 80,
            isCharging: false,
            isPluggedIn: false,
            temperatureCelsius: 30,
            voltageVolts: 12.0,
            amperageAmps: -1.0,
            adapterWatts: 0,
            cycleCount: 950,
            maxCapacityMah: 3800,
            designCapacityMah: 5000,
            permanentFailure: false
        )
        XCTAssertEqual(degraded.batteryCondition, .serviceRecommended)
    }

    private struct CIStubBatteryReader: BatteryReadingGateway {
        func readTelemetry() throws -> BatteryTelemetry {
            BatteryTelemetry(
                percentage: 75,
                isCharging: true,
                isPluggedIn: true,
                temperatureCelsius: 30.0,
                voltageVolts: 12.4,
                amperageAmps: 1.5,
                adapterWatts: 67.0,
                cycleCount: 42,
                currentCapacityMah: 3600,
                maxCapacityMah: 4800,
                designCapacityMah: 5000,
                isClamshellClosed: false
            )
        }
    }

    private func makeIsolatedInteractor() -> VoltGuardInteractor {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VoltGuardTest-\(UUID().uuidString)", isDirectory: true)
        return VoltGuardInteractor(
            batteryReader: CIStubBatteryReader(),
            smcGateway: DualModeSMCGateway(socketPath: "/tmp/nonexistent-ci-\(UUID().uuidString).sock"),
            settingsRepo: JSONSettingsRepository(fileURL: dir.appendingPathComponent("settings.json")),
            healthHistoryRepo: JSONHealthHistoryRepository(fileURL: dir.appendingPathComponent("health.json"))
        )
    }

    @MainActor
    func testCustomProfileAndSettingsReset() {
        let presenter = VoltGuardPresenter(interactor: makeIsolatedInteractor())
        presenter.dispatch(.setChargeLimit(70))
        presenter.dispatch(.setSailingDelta(6))
        presenter.dispatch(.saveCustomProfile)
        XCTAssertEqual(presenter.state.settings.customProfile?.limitPercent, 70)
        XCTAssertEqual(presenter.state.settings.customProfile?.sailingDeltaPercent, 6)

        presenter.dispatch(.setChargeLimit(90))
        presenter.dispatch(.applyCustomProfile)
        XCTAssertEqual(presenter.state.settings.policy.limitPercent, 70)

        presenter.dispatch(.resetSettingsToDefault)
        XCTAssertEqual(presenter.state.settings.policy.limitPercent, VoltGuardLimits.defaultLimitPercent)
        XCTAssertNil(presenter.state.settings.customProfile)
    }

    @MainActor
    func testCalibrationPersistenceAndLegacySettingsDecoding() throws {
        // Legacy settings JSON without calibrationSession or customProfile must decode cleanly.
        let legacyJSON = """
        {
          "policy": {
            "limitPercent": 80,
            "manualDischarge": false,
            "automaticDischarge": false,
            "dischargeInClamshell": false,
            "heatProtectionEnabled": true,
            "maxTemperatureCelsius": 35.0,
            "sailingModeEnabled": false,
            "sailingDeltaPercent": 5,
            "magSafeLEDMode": "system",
            "topUpActive": false,
            "sleepControlEnabled": true,
            "stopChargingWhenSleeping": false,
            "lowPowerModeOnBattery": false,
            "lowPowerModeAlways": false
          },
          "schedules": [],
          "locale": "id",
          "launchAtLogin": false,
          "alertsEnabled": true
        }
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.locale, .id)
        XCTAssertEqual(decoded.calibrationSession.stage, .idle)
        XCTAssertNil(decoded.customProfile)

        let presenter = VoltGuardPresenter(interactor: makeIsolatedInteractor())
        presenter.dispatch(.startCalibration)
        XCTAssertEqual(presenter.state.calibration.stage, .chargingToFull)
        XCTAssertEqual(presenter.state.settings.calibrationSession.stage, .chargingToFull)

        presenter.dispatch(.stopCalibration)
        XCTAssertEqual(presenter.state.calibration.stage, .idle)
        XCTAssertEqual(presenter.state.settings.calibrationSession.stage, .idle)
    }

    @MainActor
    func testReloadSettingsFromDiskSyncsPolicy() {
        let presenter = VoltGuardPresenter(interactor: makeIsolatedInteractor())
        presenter.dispatch(.setChargeLimit(85))
        presenter.dispatch(.reloadSettingsFromDisk)
        XCTAssertEqual(presenter.state.settings.policy.limitPercent, 85)

        var customTheme = presenter.state.settings.theme
        customTheme.useCustomBackground = true
        customTheme.customBackgroundPath = "/tmp/sample-bg.jpg"
        customTheme.backgroundScrimOpacity = 0.65
        customTheme.backgroundBlurRadius = 8.0
        presenter.dispatch(.updateTheme(customTheme))
        presenter.dispatch(.reloadSettingsFromDisk)
        XCTAssertTrue(presenter.state.settings.theme.useCustomBackground)
        XCTAssertEqual(presenter.state.settings.theme.customBackgroundPath, "/tmp/sample-bg.jpg")
        XCTAssertEqual(presenter.state.settings.theme.backgroundScrimOpacity, 0.65, accuracy: 0.001)
        XCTAssertEqual(presenter.state.settings.theme.backgroundBlurRadius, 8.0, accuracy: 0.001)
    }

    @MainActor
    func testGenerateReadmeShowcaseAssets() async throws {
        guard ProcessInfo.processInfo.environment["GENERATE_SHOWCASE"] == "1" else { return }

        final class ShowcaseBatteryReader: BatteryReadingGateway, @unchecked Sendable {
            private let lock = NSLock()
            private var sampleIndex = 0
            private let wattsCurve: [Double] = [28, 42, 58, 67, 63, 52, 46, 54, 62, 67, 61, 49, 44, 57, 67, 67]
            private let ampsCurve: [Double] = [0.85, 1.15, 1.48, 1.92, 2.35, 2.65, 2.40, 2.15, 1.80, 1.65, 1.95, 2.25, 2.05, 1.75, 1.55, 1.48]
            private let tempsCurve: [Double] = [29.4, 29.7, 30.1, 30.5, 31.0, 31.4, 31.3, 31.1, 30.8, 30.7, 30.9, 31.2, 31.0, 30.8, 30.8, 30.8]

            func readTelemetry() throws -> BatteryTelemetry {
                let idx = lock.withLock { () -> Int in
                    let i = sampleIndex % ampsCurve.count
                    sampleIndex += 1
                    return i
                }
                return BatteryTelemetry(
                    percentage: 76,
                    isCharging: true,
                    isPluggedIn: true,
                    temperatureCelsius: tempsCurve[idx],
                    voltageVolts: 12.64,
                    amperageAmps: ampsCurve[idx],
                    adapterWatts: wattsCurve[idx],
                    cycleCount: 210,
                    designCycleCount: 1000,
                    currentCapacityMah: 3264,
                    maxCapacityMah: 4295,
                    designCapacityMah: 4629,
                    isClamshellClosed: false,
                    timeRemainingMinutes: 18,
                    adapterName: "67W USB-C Power Adapter",
                    deviceName: "bq40z651"
                )
            }
        }
        final class ShowcaseSMC: SMCControlGateway, @unchecked Sendable {
            var isPrivilegedHelperConnected: Bool { true }
            var isInstalledHelperUpToDate: Bool { true }
            var isAppleSMCDriverReadable: Bool { true }
            var backendMode: SMCBackendMode { .adapterMode }
            func applyCommand(_ command: SMCCommandState) async throws {}
            func installHelper() async throws {}
            func uninstallHelper() async throws {}
        }
        final class ShowcasePower: PowerManagementGateway, @unchecked Sendable {
            func setPreventSleep(_ prevent: Bool, reason: String) {}
            func setLowPowerMode(_ enabled: Bool) async {}
        }
        final class ShowcaseLaunch: LaunchAtLoginGateway, @unchecked Sendable {
            func setEnabled(_ enabled: Bool) throws {}
            func isEnabled() -> Bool { true }
        }
        final class ShowcaseEnergyMonitor: EnergyMonitorGateway, @unchecked Sendable {
            func fetchTopEnergyApps(limit: Int) async throws -> [EnergyAppUsage] {
                [
                    EnergyAppUsage(pid: 4101, name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", cpuPercent: 34.2),
                    EnergyAppUsage(pid: 4102, name: "iOS Simulator", bundleIdentifier: "com.apple.iphonesimulator", cpuPercent: 18.7),
                    EnergyAppUsage(pid: 4103, name: "Safari", bundleIdentifier: "com.apple.Safari", cpuPercent: 11.4),
                    EnergyAppUsage(pid: 4104, name: "Figma", bundleIdentifier: "com.figma.Desktop", cpuPercent: 7.8),
                    EnergyAppUsage(pid: 4105, name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", cpuPercent: 3.1)
                ]
            }
            func terminateApp(pid: Int32) -> Bool { true }
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VoltGuardShowcase-\(UUID().uuidString)", isDirectory: true)
        let settingsRepo = JSONSettingsRepository(fileURL: dir.appendingPathComponent("settings.json"))
        let healthRepo = JSONHealthHistoryRepository(fileURL: dir.appendingPathComponent("health.json"))

        let now = Date()
        for dayOffset in (0..<14).reversed() {
            let date = now.addingTimeInterval(-Double(dayOffset) * 86400)
            let cap = 4295 + (dayOffset / 4) * 5
            let t = BatteryTelemetry(
                percentage: 76,
                isCharging: true,
                isPluggedIn: true,
                temperatureCelsius: 30.2 + Double(dayOffset % 3) * 0.4,
                voltageVolts: 12.6,
                amperageAmps: 1.4,
                adapterWatts: 67,
                cycleCount: 210 - (dayOffset / 3),
                currentCapacityMah: 3264,
                maxCapacityMah: cap,
                designCapacityMah: 4629,
                timestamp: date
            )
            _ = healthRepo.recordSnapshot(from: t)
        }

        var initialSettings = AppSettings()
        initialSettings.policy.limitPercent = 80
        initialSettings.policy.heatProtectionEnabled = true
        initialSettings.policy.sailingModeEnabled = true
        initialSettings.policy.sailingDeltaPercent = 5
        initialSettings.launchAtLogin = true
        initialSettings.alertsEnabled = true
        initialSettings.popoverLayout.hiddenModules = [.batteryHealth]
        initialSettings.menuBarIcon = MenuBarIconConfig(
            style: .shieldBattery,
            showPercentage: true,
            showWattage: true,
            showTemperature: true,
            showTimeRemaining: true
        )
        initialSettings.schedules = [
            ScheduleRule(title: "Weekday Office 80%", hour: 8, minute: 30, weekdays: [2, 3, 4, 5, 6], action: .setLimit80),
            ScheduleRule(title: "Friday Travel Top Up", hour: 17, minute: 0, weekdays: [6], action: .topUp100)
        ]
        settingsRepo.save(initialSettings)

        let interactor = VoltGuardInteractor(
            batteryReader: ShowcaseBatteryReader(),
            smcGateway: ShowcaseSMC(),
            powerGateway: ShowcasePower(),
            energyMonitor: ShowcaseEnergyMonitor(),
            settingsRepo: settingsRepo,
            healthHistoryRepo: healthRepo,
            launchAtLoginGateway: ShowcaseLaunch()
        )
        let presenter = VoltGuardPresenter(interactor: interactor)
        for _ in 0..<16 {
            await interactor.tick(settings: presenter.state.settings, calibration: presenter.state.calibration)
        }
        presenter.dispatch(.refreshEnergyApps)
        presenter.dispatch(.runDiagnostics)
        for _ in 0..<60 where presenter.state.isRunningDiagnostics || presenter.state.diagnostics == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        try? await Task.sleep(nanoseconds: 150_000_000)

        let outDir = URL(fileURLWithPath: "/Users/a2299/Documents/Projects/VoltGuard/docs/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let heroCanvas = Self.buildHeroShowcaseCanvas(presenter: presenter)
        try Self.saveViewAsPNG(heroCanvas, size: CGSize(width: 1480, height: 930), to: outDir.appendingPathComponent("voltguard-hero-showcase.png"))

        // Light theme presenter for Paper Light side-by-side comparison
        let lightRepo = JSONSettingsRepository(fileURL: dir.appendingPathComponent("light-settings.json"))
        var lightSettings = initialSettings
        lightSettings.theme = ThemeConfig(preset: .paperLight)
        lightRepo.save(lightSettings)
        let lightInteractor = VoltGuardInteractor(
            batteryReader: ShowcaseBatteryReader(),
            smcGateway: ShowcaseSMC(),
            powerGateway: ShowcasePower(),
            energyMonitor: ShowcaseEnergyMonitor(),
            settingsRepo: lightRepo,
            healthHistoryRepo: healthRepo,
            launchAtLoginGateway: ShowcaseLaunch()
        )
        let lightPresenter = VoltGuardPresenter(interactor: lightInteractor)
        await lightInteractor.tick(settings: lightPresenter.state.settings, calibration: lightPresenter.state.calibration)
        try? await Task.sleep(nanoseconds: 120_000_000)

        var calSettings = presenter.state.settings
        let calSession = CalibrationSession(
            stage: .dischargingToLow,
            stageStartedAt: Date().addingTimeInterval(-1200),
            targetLowPercent: 15,
            holdDurationSeconds: 3600
        )
        calSettings.calibrationSession = calSession
        settingsRepo.save(calSettings)
        await interactor.tick(settings: calSettings, calibration: calSession)
        try? await Task.sleep(nanoseconds: 120_000_000)

        let dualCanvas = Self.buildThemesAndCalibrationCanvas(lightPresenter: lightPresenter, darkPresenter: presenter)
        try Self.saveViewAsPNG(dualCanvas, size: CGSize(width: 1760, height: 950), to: outDir.appendingPathComponent("voltguard-themes-calibration.png"))

        let diagEnergyCanvas = Self.buildDiagnosticsAndEnergyCanvas(presenter: presenter)
        try Self.saveViewAsPNG(diagEnergyCanvas, size: CGSize(width: 1760, height: 1020), to: outDir.appendingPathComponent("voltguard-diagnostics-energy.png"))
    }

    @MainActor
    private static func studioBackdrop(accent: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#06090F"),
                    Color(hex: "#0D1520"),
                    Color(hex: "#080C12")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [accent.opacity(0.18), Color.clear],
                center: UnitPoint(x: 0.25, y: 0.18),
                startRadius: 20,
                endRadius: 680
            )
            RadialGradient(
                colors: [Color(hex: "#0EA5E9").opacity(0.12), Color.clear],
                center: UnitPoint(x: 0.82, y: 0.80),
                startRadius: 20,
                endRadius: 620
            )
        }
    }

    @MainActor
    private static func macOSWindowFrame<Content: View>(
        title: String,
        badge: String? = nil,
        accent: Color,
        borderColor: Color,
        titleBarBg: Color = Color(hex: "#151B23"),
        titleColor: Color = Color(hex: "#9AA7B8"),
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: "#FF5F56")).frame(width: 11, height: 11)
                Circle().fill(Color(hex: "#FFBD2E")).frame(width: 11, height: 11)
                Circle().fill(Color(hex: "#27C93F")).frame(width: 11, height: 11)
                Spacer()
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(titleColor)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.16))
                        .foregroundStyle(accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(titleBarBg)

            Rectangle().fill(borderColor).frame(height: 1)

            content()
                .frame(width: width, height: height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 28, y: 14)
    }

    @MainActor
    private static func buildHeroShowcaseCanvas(presenter: VoltGuardPresenter) -> some View {
        let palette = presenter.state.palette
        return ZStack {
            studioBackdrop(accent: palette.accent)

            VStack(spacing: 18) {
                // Realistic macOS Translucent Top Menu Bar Strip
                HStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                        Text("VoltGuard")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("Battery Guard & AppleSMC Control")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                    Spacer()
                    HStack(spacing: 14) {
                        MenuBarIconView(presenter: presenter)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(palette.accent.opacity(0.18))
                            .overlay(Capsule().stroke(palette.accent.opacity(0.55), lineWidth: 1))
                            .clipShape(Capsule())
                            .environment(\.colorScheme, .dark)
                        Image(systemName: "wifi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                        Text("Fri 19:55")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .overlay(Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1), alignment: .bottom)

                // Hero Headline
                HStack(alignment: .center) {
                    HStack(spacing: 14) {
                        BrandLogoView(size: 40, accentColor: palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("VoltGuard for macOS")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#F4F7FA"))
                            Text("Universal Apple Silicon (M1-M5) & Intel  |  macOS 14-27 Adapter Mode (CHIE)  |  Live Power Topology")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "#9AA7B8"))
                        }
                    }
                    Spacer()
                    Text("Universal arm64 + x86_64")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(palette.accent.opacity(0.14))
                        .foregroundStyle(palette.accent)
                        .overlay(Capsule().stroke(palette.accent.opacity(0.45), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 36)

                HStack(alignment: .top, spacing: 24) {
                    macOSWindowFrame(
                        title: "VoltGuard : Overview & Telemetry",
                        badge: "0.0% Idle CPU",
                        accent: palette.accent,
                        borderColor: palette.border,
                        width: 990,
                        height: 735
                    ) {
                        FullDashboardView(presenter: presenter, initialSection: .overview)
                    }

                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "menubar.rectangle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.accent)
                            Text("Menu Bar Popover (Cmd+Option+V)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: "#F2F4F8"))
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        PopoverView(presenter: presenter)
                            .frame(width: 340, height: 670)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(palette.accent.opacity(0.45), lineWidth: 1.2)
                            )
                            .shadow(color: Color.black.opacity(0.55), radius: 28, y: 14)
                    }
                }
                .padding(.horizontal, 36)
            }
            .padding(.bottom, 26)
        }
        .frame(width: 1480, height: 930)
        .environment(\.colorScheme, .dark)
    }

    @MainActor
    private static func buildThemesAndCalibrationCanvas(lightPresenter: VoltGuardPresenter, darkPresenter: VoltGuardPresenter) -> some View {
        let darkPalette = darkPresenter.state.palette
        let lightPalette = lightPresenter.state.palette
        return ZStack {
            studioBackdrop(accent: darkPalette.accent)

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Theme Studio (Light & Dark) & 5-Stage Guided Calibration")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#F4F7FA"))
                        Text("Paper Light & Obsidian Presets  |  Custom Wallpaper Scrim & Blur  |  Automated 5-Stage Calibration & Weekday Schedules")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "#9AA7B8"))
                    }
                    Spacer()
                }
                .padding(.horizontal, 36)

                HStack(alignment: .top, spacing: 24) {
                    macOSWindowFrame(
                        title: "Paper Light Theme & Menu Bar Studio",
                        badge: "WCAG AA Light",
                        accent: lightPalette.accent,
                        borderColor: lightPalette.border,
                        titleBarBg: Color(hex: "#ECEEF2"),
                        titleColor: Color(hex: "#4B5563"),
                        width: 825,
                        height: 790
                    ) {
                        FullDashboardView(presenter: lightPresenter, initialSection: .appearance)
                            .environment(\.colorScheme, .light)
                    }

                    macOSWindowFrame(
                        title: "5-Stage Persistent Calibration & Weekday Schedule",
                        badge: "Stage 3 Active",
                        accent: darkPalette.warning,
                        borderColor: darkPalette.border,
                        width: 825,
                        height: 790
                    ) {
                        FullDashboardView(presenter: darkPresenter, initialSection: .schedule)
                    }
                }
                .padding(.horizontal, 36)
            }
            .padding(.vertical, 24)
        }
        .frame(width: 1760, height: 950)
        .environment(\.colorScheme, .dark)
    }

    @MainActor
    private static func buildDiagnosticsAndEnergyCanvas(presenter: VoltGuardPresenter) -> some View {
        let palette = presenter.state.palette
        return ZStack {
            studioBackdrop(accent: palette.accent)

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Energy Monitor, Self-Diagnostic & Crash Guard")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#F4F7FA"))
                        Text("Identify Power-Hungry Apps  |  7-Point Hardware & Helper Self-Test  |  Native Crash & Signal Protection")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "#9AA7B8"))
                    }
                    Spacer()
                }
                .padding(.horizontal, 36)

                HStack(alignment: .top, spacing: 24) {
                    macOSWindowFrame(
                        title: "Energy Monitor : Top Power Consumers",
                        badge: "Real-Time Sampling",
                        accent: palette.accent,
                        borderColor: palette.border,
                        width: 825,
                        height: 870
                    ) {
                        FullDashboardView(presenter: presenter, initialSection: .energy)
                    }

                    macOSWindowFrame(
                        title: "System Diagnostics & AppleSMC Guard",
                        badge: "7/7 Passed",
                        accent: palette.accent,
                        borderColor: palette.border,
                        width: 825,
                        height: 870
                    ) {
                        FullDashboardView(presenter: presenter, initialSection: .system)
                    }
                }
                .padding(.horizontal, 36)
            }
            .padding(.vertical, 24)
        }
        .frame(width: 1760, height: 1020)
        .environment(\.colorScheme, .dark)
    }

    @MainActor
    private static func saveViewAsPNG<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        hostingView.layoutSubtreeIfNeeded()

        let pixelWidth = Int(size.width * 2)
        let pixelHeight = Int(size.height * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "ShowcaseRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap"])
        }
        rep.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ShowcaseRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try pngData.write(to: url, options: .atomic)
    }
}

final class VoltGuardStabilityTests: XCTestCase {
    func testCrashReporterExceptionAndUncleanExitLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voltguard-crash-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let reporter = CrashReporter(crashesDirectoryURL: tempDir)
        reporter.install(registerProcessHandlers: false)
        XCTAssertTrue(reporter.loadReports().isEmpty)

        // Simulate unclean exit by installing again without markCleanExit()
        reporter.install(registerProcessHandlers: false)
        let afterUnclean = reporter.loadReports()
        XCTAssertEqual(afterUnclean.count, 1)
        XCTAssertEqual(afterUnclean.first?.type, "unclean_exit")

        // Record an exception report
        reporter.recordException(
            name: "NSInvalidArgumentException",
            reason: "Simulated crash",
            callStack: ["0 VoltGuard 0x00000001 test"]
        )
        let reports = reporter.loadReports()
        XCTAssertEqual(reports.count, 2)
        XCTAssertTrue(reports.contains { $0.type == "exception" && $0.name == "NSInvalidArgumentException" })

        reporter.clearReports()
        XCTAssertTrue(reporter.loadReports().isEmpty)
        reporter.markCleanExit()
    }

    @MainActor
    func testWeakDeallocationOfInteractorGatewaysAndCrashReporter() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voltguard-leak-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        weak var weakInteractor: VoltGuardInteractor?
        weak var weakPowerGateway: SystemPowerGateway?
        weak var weakSMC: DualModeSMCGateway?
        weak var weakCrashReporter: CrashReporter?

        autoreleasepool {
            let smc = DualModeSMCGateway(socketPath: "/tmp/nonexistent-voltguard-\(UUID().uuidString).sock")
            let power = SystemPowerGateway()
            let crash = CrashReporter(crashesDirectoryURL: tempDir)
            let settingsRepo = JSONSettingsRepository(fileURL: tempDir.appendingPathComponent("settings.json"))
            let historyRepo = JSONHealthHistoryRepository(fileURL: tempDir.appendingPathComponent("history.json"))
            let interactor = VoltGuardInteractor(
                batteryReader: IOKitBatteryReader(),
                smcGateway: smc,
                powerGateway: power,
                energyMonitor: SystemEnergyMonitor(),
                settingsRepo: settingsRepo,
                healthHistoryRepo: historyRepo,
                launchAtLoginGateway: SystemLaunchAtLoginGateway(),
                alertGateway: SystemAlertNotificationGateway()
            )
            _ = interactor.runDiagnostics(alertsEnabled: false)
            weakInteractor = interactor
            weakPowerGateway = power
            weakSMC = smc
            weakCrashReporter = crash
        }

        XCTAssertNil(weakInteractor, "VoltGuardInteractor must not retain-cycle")
        XCTAssertNil(weakPowerGateway, "SystemPowerGateway must not retain-cycle")
        XCTAssertNil(weakSMC, "DualModeSMCGateway must not retain-cycle")
        XCTAssertNil(weakCrashReporter, "CrashReporter must not retain-cycle")
    }

    func testDualModeSMCGatewaySocketProbeFailsCleanlyWithoutSIGPIPE() {
        let nonexistentSocket = "/tmp/voltguard-missing-\(UUID().uuidString).sock"
        let gateway = DualModeSMCGateway(socketPath: nonexistentSocket)
        XCTAssertFalse(gateway.probeLiveConnection())
    }

    @MainActor
    func testAnimatedDiagnosticsSelfTestLifecycle() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voltguard-diag-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let interactor = VoltGuardInteractor(
            batteryReader: IOKitBatteryReader(),
            smcGateway: DualModeSMCGateway(socketPath: "/tmp/nonexistent-diag-\(UUID().uuidString).sock"),
            powerGateway: SystemPowerGateway(),
            energyMonitor: SystemEnergyMonitor(),
            settingsRepo: JSONSettingsRepository(fileURL: tempDir.appendingPathComponent("settings.json")),
            healthHistoryRepo: JSONHealthHistoryRepository(fileURL: tempDir.appendingPathComponent("history.json")),
            launchAtLoginGateway: SystemLaunchAtLoginGateway(),
            alertGateway: SystemAlertNotificationGateway()
        )
        let presenter = VoltGuardPresenter(interactor: interactor)
        presenter.dispatch(.runDiagnostics)
        XCTAssertTrue(presenter.state.isRunningDiagnostics)

        for _ in 0..<60 where presenter.state.isRunningDiagnostics || presenter.state.diagnostics == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(presenter.state.isRunningDiagnostics)
        XCTAssertEqual(presenter.state.diagnosticsScanStep, 8)
        XCTAssertNotNil(presenter.state.diagnostics)
    }

    func testAutoDischargeHysteresisReachesTargetLimit() {
        let useCase = EvaluateChargePolicyUseCase()
        var policy = ChargePolicy(limitPercent: 80)
        policy.automaticDischarge = true
        policy.sailingModeEnabled = false

        func telemetry(_ pct: Int) -> BatteryTelemetry {
            BatteryTelemetry(
                percentage: pct,
                isCharging: false,
                isPluggedIn: true,
                temperatureCelsius: 30,
                voltageVolts: 12.2,
                amperageAmps: 0.0,
                adapterWatts: 30,
                cycleCount: 100,
                currentCapacityMah: pct * 40,
                maxCapacityMah: 4000,
                designCapacityMah: 4500
            )
        }

        // Above 82% triggers auto discharge
        let r1 = useCase.execute(telemetry: telemetry(85), policy: policy, calibration: CalibrationSession(), context: PolicyEvaluationContext())
        XCTAssertTrue(r1.command.forceDischarge)
        XCTAssertEqual(r1.command.statusReason, .automaticDischarge)

        // Still keeps discharging at 81% (previously stopped prematurely at 82%)
        let r2 = useCase.execute(telemetry: telemetry(81), policy: policy, calibration: CalibrationSession(), context: r1.updatedContext)
        XCTAssertTrue(r2.command.forceDischarge)
        XCTAssertEqual(r2.command.statusReason, .automaticDischarge)

        // Stops once it reaches target limit 80%
        let r3 = useCase.execute(telemetry: telemetry(80), policy: policy, calibration: CalibrationSession(), context: r2.updatedContext)
        XCTAssertFalse(r3.command.forceDischarge)
        XCTAssertFalse(r3.command.allowCharging)
    }

    func testAdapterModeMinHysteresisBandPreventsPingPong() {
        let useCase = EvaluateChargePolicyUseCase()
        var policy = ChargePolicy(limitPercent: 80)
        policy.sailingModeEnabled = false

        func telemetry(_ pct: Int) -> BatteryTelemetry {
            BatteryTelemetry(
                percentage: pct,
                isCharging: true,
                isPluggedIn: true,
                temperatureCelsius: 30,
                voltageVolts: 12.2,
                amperageAmps: 1.0,
                adapterWatts: 30,
                cycleCount: 100,
                currentCapacityMah: pct * 40,
                maxCapacityMah: 4000,
                designCapacityMah: 4500
            )
        }

        let atLimit = useCase.execute(telemetry: telemetry(80), policy: policy, calibration: CalibrationSession(), context: PolicyEvaluationContext(), adapterCutMode: true)
        XCTAssertFalse(atLimit.command.allowCharging)
        XCTAssertEqual(atLimit.command.statusReason, .limitReached)

        // Stays paused at 79% and 78% inside 3% adapter-mode hysteresis band
        let at79 = useCase.execute(telemetry: telemetry(79), policy: policy, calibration: CalibrationSession(), context: atLimit.updatedContext, adapterCutMode: true)
        XCTAssertFalse(at79.command.allowCharging)

        // Resumes charging at 77% (80 - 3)
        let at77 = useCase.execute(telemetry: telemetry(77), policy: policy, calibration: CalibrationSession(), context: at79.updatedContext, adapterCutMode: true)
        XCTAssertTrue(at77.command.allowCharging)
        XCTAssertEqual(at77.command.statusReason, .normalCharging)
    }

    @MainActor
    func testTopUpAndManualDischargeMutualExclusion() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voltguard-excl-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let interactor = VoltGuardInteractor(
            batteryReader: IOKitBatteryReader(),
            smcGateway: DualModeSMCGateway(socketPath: "/tmp/nonexistent-excl-\(UUID().uuidString).sock"),
            powerGateway: SystemPowerGateway(),
            energyMonitor: SystemEnergyMonitor(),
            settingsRepo: JSONSettingsRepository(fileURL: tempDir.appendingPathComponent("settings.json")),
            healthHistoryRepo: JSONHealthHistoryRepository(fileURL: tempDir.appendingPathComponent("history.json")),
            launchAtLoginGateway: SystemLaunchAtLoginGateway(),
            alertGateway: SystemAlertNotificationGateway()
        )
        let presenter = VoltGuardPresenter(interactor: interactor)
        presenter.dispatch(.toggleManualDischarge)
        XCTAssertTrue(presenter.state.settings.policy.manualDischarge)

        presenter.dispatch(.toggleTopUp)
        XCTAssertTrue(presenter.state.settings.policy.topUpActive)
        XCTAssertFalse(presenter.state.settings.policy.manualDischarge)

        presenter.dispatch(.toggleManualDischarge)
        XCTAssertTrue(presenter.state.settings.policy.manualDischarge)
        XCTAssertFalse(presenter.state.settings.policy.topUpActive)
    }

    func testSailingModeStepsDownWhenAboveLimit() {
        let useCase = EvaluateChargePolicyUseCase()
        var policy = ChargePolicy(limitPercent: 80)
        policy.sailingModeEnabled = true
        policy.sailingDeltaPercent = 5
        policy.automaticDischarge = false

        func telemetry(_ pct: Int) -> BatteryTelemetry {
            BatteryTelemetry(
                percentage: pct,
                isCharging: false,
                isPluggedIn: true,
                temperatureCelsius: 28,
                voltageVolts: 12.8,
                amperageAmps: 0.0,
                adapterWatts: 65,
                cycleCount: 120,
                currentCapacityMah: pct * 42,
                maxCapacityMah: 4200,
                designCapacityMah: 4629
            )
        }

        // At 100% with Sailing enabled and limit 80%, should actively step down (forceDischarge = true).
        let at100 = useCase.execute(telemetry: telemetry(100), policy: policy, calibration: CalibrationSession(), context: PolicyEvaluationContext(), adapterCutMode: true)
        XCTAssertFalse(at100.command.allowCharging)
        XCTAssertTrue(at100.command.forceDischarge)
        XCTAssertEqual(at100.command.statusReason, .sailingPaused)

        // At 81%, still stepping down toward 80% / sailing band.
        let at81 = useCase.execute(telemetry: telemetry(81), policy: policy, calibration: CalibrationSession(), context: at100.updatedContext, adapterCutMode: true)
        XCTAssertTrue(at81.command.forceDischarge)
        XCTAssertEqual(at81.command.statusReason, .sailingPaused)

        // Once inside [75%...80%], stop force-discharging and hold cleanly in sailing band.
        let at80 = useCase.execute(telemetry: telemetry(80), policy: policy, calibration: CalibrationSession(), context: at81.updatedContext, adapterCutMode: true)
        XCTAssertFalse(at80.command.forceDischarge)
        XCTAssertFalse(at80.command.allowCharging)
        XCTAssertEqual(at80.command.statusReason, .sailingPaused)

        let at76 = useCase.execute(telemetry: telemetry(76), policy: policy, calibration: CalibrationSession(), context: at80.updatedContext, adapterCutMode: true)
        XCTAssertFalse(at76.command.forceDischarge)
        XCTAssertFalse(at76.command.allowCharging)
        XCTAssertEqual(at76.command.statusReason, .sailingPaused)
    }

    func testTargetAwareETADuringSailingAndLimitHold() {
        var calc = BatteryETACalculator()
        let t = BatteryTelemetry(
            percentage: 100,
            isCharging: false,
            isPluggedIn: true,
            temperatureCelsius: 25,
            voltageVolts: 13.0,
            amperageAmps: -0.61,
            adapterWatts: 65,
            cycleCount: 211,
            currentCapacityMah: 4297,
            maxCapacityMah: 4297,
            designCapacityMah: 4629,
            timeRemainingMinutes: 428
        )

        // Plugged in & stepping down toward 80% should target 80%, never "to empty".
        let eta = calc.update(telemetry: t, targetLimit: 80, dischargeTargetPercent: 80)
        XCTAssertEqual(eta.kind, .toCalibrationTarget)
        XCTAssertEqual(eta.targetPercent, 80)
        XCTAssertNotNil(eta.minutes)

        // Zero current plugged-in transition should settle to .steady rather than nil/"Calculating time...".
        var zeroCalc = BatteryETACalculator()
        let zeroT = BatteryTelemetry(
            percentage: 80,
            isCharging: false,
            isPluggedIn: true,
            temperatureCelsius: 25,
            voltageVolts: 13.0,
            amperageAmps: 0.0,
            adapterWatts: 65,
            cycleCount: 211,
            currentCapacityMah: 3437,
            maxCapacityMah: 4297,
            designCapacityMah: 4629
        )
        let steadyEta = zeroCalc.update(telemetry: zeroT, targetLimit: 80, dischargeTargetPercent: 80)
        XCTAssertEqual(steadyEta.kind, .steady)
        XCTAssertEqual(steadyEta.targetPercent, 80)
    }

    func testBatteryColorStyleAndMatchBatteryLEDPersistence() throws {
        var settings = AppSettings()
        settings.policy.magSafeLEDMode = .matchBattery
        settings.theme.batteryColorStyle = .thermalReactive

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.policy.magSafeLEDMode, .matchBattery)
        XCTAssertEqual(decoded.theme.batteryColorStyle, .thermalReactive)

        let useCase = EvaluateChargePolicyUseCase()
        var hotPolicy = ChargePolicy(limitPercent: 80)
        hotPolicy.magSafeLEDMode = .matchBattery
        let hotTelemetry = BatteryTelemetry(
            percentage: 78,
            isCharging: false,
            isPluggedIn: true,
            temperatureCelsius: 42,
            voltageVolts: 12.6,
            amperageAmps: 0.0,
            adapterWatts: 65,
            cycleCount: 50,
            currentCapacityMah: 3300,
            maxCapacityMah: 4200,
            designCapacityMah: 4500
        )
        let hotResult = useCase.execute(telemetry: hotTelemetry, policy: hotPolicy, calibration: CalibrationSession(), context: PolicyEvaluationContext())
        XCTAssertEqual(hotResult.command.magSafeLED, .amber)
    }

    func testIOKitBatteryReaderParsesAdapterPDDetails() {
        let props: [String: Any] = [
            "CurrentCapacity": 85,
            "MaxCapacity": 100,
            "IsCharging": false,
            "ExternalConnected": true,
            "Temperature": 2980,
            "Voltage": 12800,
            "Amperage": 0,
            "AdapterDetails": [
                "Watts": 67,
                "Name": "Apple 67W USB-C Power Adapter",
                "Description": "usb pd",
                "AdapterVoltage": 20000,
                "Current": 3350
            ]
        ]

        let telemetry = IOKitBatteryReader.parseRegistryProperties(props)
        XCTAssertEqual(telemetry.adapterWatts, 67)
        XCTAssertEqual(telemetry.adapterName, "Apple 67W USB-C Power Adapter")
        XCTAssertEqual(telemetry.adapterVoltageVolts ?? 0, 20.0, accuracy: 0.01)
        XCTAssertEqual(telemetry.adapterCurrentAmps ?? 0, 3.35, accuracy: 0.01)
        XCTAssertEqual(telemetry.adapterProtocol, "usb pd")
    }

    func testMacHardwareProfileCapabilitiesAndWritableKeys() {
        let profileWithMagSafe = MacHardwareProfile.detectCurrent(writableKeys: ["CHIE", "ACLC"], hasBatteryService: true)
        XCTAssertFalse(profileWithMagSafe.isDesktopMac)
        XCTAssertTrue(profileWithMagSafe.supportsMagSafeLED)

        let profileWithoutMagSafe = MacHardwareProfile.detectCurrent(writableKeys: ["CH0B", "CH0C", "CH0I"], hasBatteryService: true)
        XCTAssertFalse(profileWithoutMagSafe.isDesktopMac)
        XCTAssertFalse(profileWithoutMagSafe.supportsMagSafeLED)

        let desktopProfile = MacHardwareProfile.detectCurrent(writableKeys: [], hasBatteryService: false)
        XCTAssertTrue(desktopProfile.isDesktopMac)
        XCTAssertFalse(desktopProfile.supportsMagSafeLED)
        XCTAssertFalse(desktopProfile.supportsLowPowerMode)
    }

    func testCompatibilityAuditRunsOnceAndCachesByFingerprint() throws {
        let laptopProfile = MacHardwareProfile(
            modelIdentifier: "Mac16,12",
            architecture: "arm64",
            macOSVersionString: "27.2.1",
            macOSMajorVersion: 27,
            isDesktopMac: false,
            isAppleSilicon: true,
            supportsMagSafeLED: true,
            supportsLowPowerMode: true
        )

        let report1 = CachedCompatibilityReport.evaluateOnce(
            profile: laptopProfile,
            backendMode: .adapterMode,
            writableKeys: ["CHIE", "ACLC"],
            helperConnected: true,
            helperSignature: "v1"
        )
        XCTAssertTrue(report1.chargeLimit.supported)
        XCTAssertTrue(report1.discharge.supported)
        XCTAssertFalse(report1.magSafeLED.supported)
        XCTAssertEqual(report1.magSafeLED.reasonCode, "adapter_mode_cuts_magsafe")

        // Persistence round-trip inside AppSettings
        var settings = AppSettings()
        settings.cachedCompatibility = report1
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.cachedCompatibility?.fingerprint, report1.fingerprint)

        // Matching fingerprint skips re-evaluation unless helper/OS/mode changes
        let sameFp = CachedCompatibilityReport.makeFingerprint(
            profile: laptopProfile,
            backendMode: .adapterMode,
            writableKeys: ["ACLC", "CHIE"],
            helperConnected: true,
            helperSignature: "v1"
        )
        XCTAssertEqual(sameFp, report1.fingerprint)

        let changedFp = CachedCompatibilityReport.makeFingerprint(
            profile: laptopProfile,
            backendMode: .legacy,
            writableKeys: ["CHTE", "ACLC"],
            helperConnected: true,
            helperSignature: "v2"
        )
        XCTAssertNotEqual(changedFp, report1.fingerprint)
    }

    func testMagSafeLEDDisabledInAdapterModeAndUnsupportedTogglesBlocked() {
        let laptopProfile = MacHardwareProfile(
            modelIdentifier: "Mac16,12",
            architecture: "arm64",
            macOSVersionString: "27.2.1",
            macOSMajorVersion: 27,
            isDesktopMac: false,
            isAppleSilicon: true,
            supportsMagSafeLED: true,
            supportsLowPowerMode: true
        )
        let compat = CachedCompatibilityReport.evaluateOnce(
            profile: laptopProfile,
            backendMode: .adapterMode,
            writableKeys: ["CHIE", "ACLC"],
            helperConnected: true,
            helperSignature: "v1"
        )
        let useCase = EvaluateChargePolicyUseCase()
        var policy = ChargePolicy(limitPercent: 80)
        policy.magSafeLEDMode = .amber
        let telemetry = BatteryTelemetry(
            percentage: 75,
            isCharging: true,
            isPluggedIn: true,
            temperatureCelsius: 30,
            voltageVolts: 12.2,
            amperageAmps: 1.5,
            adapterWatts: 30,
            cycleCount: 100,
            currentCapacityMah: 3000,
            maxCapacityMah: 4000,
            designCapacityMah: 4500
        )
        let eval = useCase.execute(
            telemetry: telemetry,
            policy: policy,
            calibration: CalibrationSession(),
            context: PolicyEvaluationContext(),
            adapterCutMode: true,
            compatibility: compat
        )
        XCTAssertEqual(eval.command.magSafeLED, .system)
    }

    func testAppleSMCThermistorDecodingAndCalibrationResultRecord() {
        // IEEE-754 float 30.3 C ("flt ") -> 0x41F26666
        let float30_3 = IOKitBatteryReader.decodeSMCTemperature(bytes: [0x66, 0x66, 0xF2, 0x41], dataType: "flt ")
        XCTAssertNotNil(float30_3)
        XCTAssertEqual(float30_3 ?? 0, 30.3, accuracy: 0.05)

        // Signed 7.8 fixed-point 34.5 C ("sp78") -> 34 * 256 + 128 = 0x2280
        let sp78_34_5 = IOKitBatteryReader.decodeSMCTemperature(bytes: [0x22, 0x80], dataType: "sp78")
        XCTAssertNotNil(sp78_34_5)
        XCTAssertEqual(sp78_34_5 ?? 0, 34.5, accuracy: 0.05)

        // Out-of-bounds value is rejected cleanly
        XCTAssertNil(IOKitBatteryReader.decodeSMCTemperature(bytes: [0x00, 0x00, 0xC8, 0x42], dataType: "flt "))

        let record = CalibrationResultRecord(
            startedAt: Date(timeIntervalSince1970: 1000),
            completedAt: Date(timeIntervalSince1970: 5000),
            beforeMaxCapacityMah: 4100,
            afterMaxCapacityMah: 4220,
            beforeHealthPercent: 89,
            afterHealthPercent: 92,
            beforeCycleCount: 120,
            afterCycleCount: 121
        )
        XCTAssertEqual(record.deltaMah, 120)
        XCTAssertEqual(record.deltaHealthPercent, 3)
    }

    func testAppReleaseSemverComparisonAndRestoreOnQuitPolicy() throws {
        XCTAssertTrue(AppReleaseInfo.isNewerVersion("1.3.0", than: "1.2.0"))
        XCTAssertTrue(AppReleaseInfo.isNewerVersion("v1.2.1", than: "1.2.0"))
        XCTAssertFalse(AppReleaseInfo.isNewerVersion("1.2.0", than: "1.2.0"))
        XCTAssertFalse(AppReleaseInfo.isNewerVersion("1.1.9", than: "1.2.0"))
        XCTAssertFalse(AppReleaseInfo.changelog.isEmpty)

        // Ensure legacy ChargePolicy JSON without restoreDefaultOnQuit decodes safely with default true.
        let legacyJSON = """
        {"limitPercent":80,"manualDischarge":false,"automaticDischarge":false,"dischargeInClamshell":false,"heatProtectionEnabled":true,"maxTemperatureCelsius":35,"sailingModeEnabled":false,"sailingDeltaPercent":5,"magSafeLEDMode":"syncWithLimit","topUpActive":false,"sleepControlEnabled":true,"stopChargingWhenSleeping":false,"lowPowerModeOnBattery":false,"lowPowerModeAlways":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ChargePolicy.self, from: legacyJSON)
        XCTAssertTrue(decoded.restoreDefaultOnQuit)
    }
}
