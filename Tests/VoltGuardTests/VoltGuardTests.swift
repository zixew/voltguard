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
        let start = Date(timeIntervalSince1970: 1000)
        var session = CalibrationSession(stage: .chargingToFull, stageStartedAt: start, targetLowPercent: 15, holdDurationSeconds: 60)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 100), targetLimit: 80, now: start.addingTimeInterval(10))
        XCTAssertEqual(session.stage, .holdingFull)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 100), targetLimit: 80, now: start.addingTimeInterval(80))
        XCTAssertEqual(session.stage, .dischargingToLow)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 15), targetLimit: 80, now: start.addingTimeInterval(200))
        XCTAssertEqual(session.stage, .holdingLow)

        session = machine.advance(session: session, telemetry: sampleTelemetry(pct: 15), targetLimit: 80, now: start.addingTimeInterval(270))
        XCTAssertEqual(session.stage, .restoringLimit)

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
    func testPresenterFullFeatureDispatchAndRouter() {
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
            func readTelemetry() throws -> BatteryTelemetry {
                BatteryTelemetry(
                    percentage: 60,
                    isCharging: true,
                    isPluggedIn: true,
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

        let alerts = MockAlerts()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("voltguard-alert-\(UUID().uuidString).json")
        let interactor = VoltGuardInteractor(
            batteryReader: MockBatteryReader(),
            smcGateway: MockSMC(),
            powerGateway: MockPower(),
            settingsRepo: JSONSettingsRepository(fileURL: tempURL),
            alertGateway: alerts
        )
        let settings = AppSettings(alertsEnabled: true)
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        await interactor.tick(settings: settings, calibration: CalibrationSession())
        XCTAssertEqual(alerts.sentIDs, ["voltguard.heat"], "Heat alert should fire once per transition")
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
    func testPopoverModuleReorderAndDiagnostics() {
        let interactor = makeIsolatedInteractor()
        let presenter = VoltGuardPresenter(interactor: interactor)

        let initialFirst = presenter.state.settings.popoverLayout.orderedModules[0]
        let initialSecond = presenter.state.settings.popoverLayout.orderedModules[1]
        presenter.dispatch(.movePopoverModule(initialFirst, 1))
        XCTAssertEqual(presenter.state.settings.popoverLayout.orderedModules[0], initialSecond)
        XCTAssertEqual(presenter.state.settings.popoverLayout.orderedModules[1], initialFirst)

        presenter.dispatch(.runDiagnostics)
        XCTAssertNotNil(presenter.state.diagnostics)
    }

    func testBatteryETACalculatorToEmptyAndToLimit() {
        var calc = BatteryETACalculator()

        // 50% of 4800 mAh = 2400 mAh; draining at -1.0 A -> 144 min
        let draining = sampleTelemetry(pct: 50, isCharging: false, isPluggedIn: false, amperage: -1.0)
        let etaEmpty = calc.update(telemetry: draining, targetLimit: 80)
        XCTAssertEqual(etaEmpty.kind, .toEmpty)
        XCTAssertEqual(etaEmpty.minutes, 144)

        // 50% -> 80% of 4800 mAh = 1440 mAh needed; charging at +1.5 A -> 57 min
        let charging = sampleTelemetry(pct: 50, isCharging: true, isPluggedIn: true, amperage: 1.5)
        let etaLimit = calc.update(telemetry: charging, targetLimit: 80)
        XCTAssertEqual(etaLimit.kind, .toTargetLimit)
        XCTAssertEqual(etaLimit.minutes, 57)

        // Charging below limit with near-zero initial current -> calculating state
        var lowCurrentCalc = BatteryETACalculator()
        let lowCurrent = sampleTelemetry(pct: 50, isCharging: true, isPluggedIn: true, amperage: 0.01)
        let etaCalculating = lowCurrentCalc.update(telemetry: lowCurrent, targetLimit: 80)
        XCTAssertEqual(etaCalculating.kind, .toTargetLimit)
        XCTAssertNil(etaCalculating.minutes)
        XCTAssertEqual(etaCalculating.targetPercent, 80)

        // At target limit while plugged in -> steady
        let atLimit = sampleTelemetry(pct: 80, isCharging: false, isPluggedIn: true, amperage: 0.0)
        let etaSteady = lowCurrentCalc.update(telemetry: atLimit, targetLimit: 80)
        XCTAssertEqual(etaSteady.kind, .steady)
        XCTAssertEqual(etaSteady.targetPercent, 80)

        // Formatting checks (ID & EN)
        XCTAssertEqual(BatteryETAFormatter.text(for: etaEmpty, locale: .id), "2j 24m sampai habis")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaEmpty, locale: .en), "2h 24m until empty")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaLimit, locale: .id), "57m sampai penuh 80%")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaLimit, locale: .en), "57m to 80% full")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaSteady, locale: .id), "Batas 80% tercapai")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaSteady, locale: .en), "80% limit reached")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaCalculating, locale: .id), "Menghitung sisa waktu...")
        XCTAssertEqual(BatteryETAFormatter.text(for: etaCalculating, locale: .en), "Calculating time...")
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

        // Sudden 2-second CPU spike (-3.0 A) must be damped by time-aware EMA and ±1 min rate limit.
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
        XCTAssertEqual(etaSpike.minutes, 143)

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

    private func makeIsolatedInteractor() -> VoltGuardInteractor {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VoltGuardTest-\(UUID().uuidString)", isDirectory: true)
        return VoltGuardInteractor(
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
}
