import AppKit
import Combine
import SwiftUI
import VoltGuardData
import VoltGuardDomain

public enum TelemetryLoadState: Equatable {
    case loading
    case loaded(BatteryTelemetry, PowerFlowMetrics)
    case error(String)
}

public enum EnergyListState: Equatable {
    case idle
    case loading
    case loaded([EnergyAppUsage])
    case error(String)
}

public struct TelemetrySample: Equatable, Sendable {
    public let watts: Double
    public let temperatureCelsius: Double

    public init(watts: Double, temperatureCelsius: Double) {
        self.watts = watts
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct ActivityLogEntry: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let messageKey: L10nKey

    public init(id: UUID = UUID(), timestamp: Date = Date(), messageKey: L10nKey) {
        self.id = id
        self.timestamp = timestamp
        self.messageKey = messageKey
    }
}

public enum ToolbarEventAction: Equatable, Sendable {
    case topUp100
    case stopDischarge
    case enableLowPowerOnBattery
    case openEnergyMonitor
    case openCalibration
    case openFullApp
}

public enum ToolbarEventSeverity: Equatable, Sendable {
    case accent
    case warning
    case danger
}

public struct ToolbarNotificationEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let icon: String
    public let titleKey: L10nKey
    public let bodyKey: L10nKey
    public let severity: ToolbarEventSeverity
    public let actionTitleKey: L10nKey?
    public let action: ToolbarEventAction?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        icon: String,
        titleKey: L10nKey,
        bodyKey: L10nKey,
        severity: ToolbarEventSeverity,
        actionTitleKey: L10nKey? = nil,
        action: ToolbarEventAction? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.icon = icon
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.severity = severity
        self.actionTitleKey = actionTitleKey
        self.action = action
        self.createdAt = createdAt
    }
}

public struct VoltGuardViewState: Equatable {
    public var telemetryState: TelemetryLoadState = .loading
    public var telemetryHistory: [TelemetrySample] = []
    public var batteryETA: BatteryETA?
    public var healthSnapshots: [BatteryHealthSnapshot] = []
    public var activityLog: [ActivityLogEntry] = []
    public var activeToolbarEvent: ToolbarNotificationEvent?
    public var requestedDashboardTab: Int?
    public var diagnostics: DiagnosticsReport?
    public var csvExportFeedback: Bool = false
    public var settingsFeedbackMessage: String?
    public var isUIVisible: Bool = false
    public var energyState: EnergyListState = .idle
    public var liveRecommendation: ProfileRecommendation?
    public var settings: AppSettings = AppSettings()
    public var calibration: CalibrationSession = CalibrationSession()
    public var lastReason: PolicyReason = .normalCharging
    public var helperConnected: Bool = false
    public var helperErrorMessage: String?
    public var palette: ThemePalette = ThemePalette.resolve(ThemeConfig())
}

public enum VoltGuardAction {
    case refreshTelemetry
    case refreshEnergyApps
    case terminateEnergyApp(Int32)
    case applyProfileTier(BatteryProfileTier)
    case setChargeLimit(Int)
    case toggleManualDischarge
    case toggleAutomaticDischarge
    case toggleClamshellDischarge
    case toggleHeatProtection
    case setMaxTemperature(Double)
    case toggleSailingMode
    case setSailingDelta(Int)
    case setMagSafeLED(MagSafeLEDMode)
    case toggleTopUp
    case startCalibration
    case stopCalibration
    case toggleSleepControl
    case toggleStopChargingOnSleep
    case toggleLowPowerOnBattery
    case toggleLowPowerAlways
    case addScheduleRule(ScheduleRule)
    case toggleScheduleRule(UUID)
    case removeScheduleRule(UUID)
    case updateTheme(ThemeConfig)
    case updateLocale(AppLocale)
    case updateMenuBarConfig(MenuBarIconConfig)
    case updatePopoverLayout(PopoverModuleConfig)
    case movePopoverModule(PopoverModuleID, Int)
    case exportHealthCSV
    case runDiagnostics
    case toggleLaunchAtLogin
    case toggleSmartAlerts
    case saveCustomProfile
    case applyCustomProfile
    case exportSettingsJSON
    case importSettingsJSON(String)
    case resetSettingsToDefault
    case reloadSettingsFromDisk
    case installHelper
    case uninstallHelper
    case openFullApp
    case minimizeToBackground
    case hideMenuBarIcon
    case dismissToolbarEvent
    case triggerToolbarEventAction(ToolbarEventAction)
    case testToolbarEvent
    case quitApp
}

public final class VoltGuardInteractor {
    private let batteryReader: BatteryReadingGateway
    private let smcGateway: SMCControlGateway
    private let powerGateway: PowerManagementGateway
    private let energyMonitor: EnergyMonitorGateway
    private let settingsRepo: SettingsRepository
    private let healthHistoryRepo: HealthHistoryRepository
    private let launchAtLoginGateway: LaunchAtLoginGateway
    private let alertGateway: AlertNotificationGateway

    private let policyUseCase = EvaluateChargePolicyUseCase()
    private let calibrationUseCase = CalibrationMachineUseCase()
    private let scheduleUseCase = ScheduleEvaluatorUseCase()
    private let powerFlowCalculator = PowerFlowCalculator()

    private var policyContext = PolicyEvaluationContext()
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.voltguard.telemetry", qos: .utility)
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lastScheduleMinuteKey: String = ""
    private var previousStatusReason: PolicyReason = .normalCharging
    private var wasLowBatteryAlerted: Bool = false

    public var onStateUpdate: ((BatteryTelemetry?, PowerFlowMetrics, AppSettings, CalibrationSession, PolicyReason, Bool, [BatteryHealthSnapshot]?, String?) -> Void)?

    public init(
        batteryReader: BatteryReadingGateway = IOKitBatteryReader(),
        smcGateway: SMCControlGateway = DualModeSMCGateway(),
        powerGateway: PowerManagementGateway = SystemPowerGateway(),
        energyMonitor: EnergyMonitorGateway = SystemEnergyMonitor(),
        settingsRepo: SettingsRepository = JSONSettingsRepository(),
        healthHistoryRepo: HealthHistoryRepository = JSONHealthHistoryRepository(),
        launchAtLoginGateway: LaunchAtLoginGateway = SystemLaunchAtLoginGateway(),
        alertGateway: AlertNotificationGateway = SystemAlertNotificationGateway()
    ) {
        self.batteryReader = batteryReader
        self.smcGateway = smcGateway
        self.powerGateway = powerGateway
        self.energyMonitor = energyMonitor
        self.settingsRepo = settingsRepo
        self.healthHistoryRepo = healthHistoryRepo
        self.launchAtLoginGateway = launchAtLoginGateway
        self.alertGateway = alertGateway
        observeSleepWake()
    }

    deinit {
        stopPolling()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    public func loadInitialSettings() -> AppSettings {
        settingsRepo.load()
    }

    public func saveSettings(_ settings: AppSettings) {
        settingsRepo.save(settings)
    }

    public func startPolling(intervalSeconds: TimeInterval, settingsProvider: @escaping () -> (AppSettings, CalibrationSession)) {
        stopPolling()
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now(), repeating: intervalSeconds, leeway: .milliseconds(AppLayoutConstants.telemetryLeewayMs))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let (settings, calibration) = settingsProvider()
            Task { [weak self] in
                await self?.tick(settings: settings, calibration: calibration)
            }
        }
        timer = source
        source.resume()
    }

    public func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    public func fetchTopEnergyApps() async throws -> [EnergyAppUsage] {
        try await energyMonitor.fetchTopEnergyApps(limit: AppLayoutConstants.energyTopAppCount)
    }

    @MainActor
    public func terminateEnergyApp(pid: Int32) -> Bool {
        energyMonitor.terminateApp(pid: pid)
    }

    public func tick(settings: AppSettings, calibration: CalibrationSession) async {
        do {
            let telemetry = try batteryReader.readTelemetry()
            var mutableSettings = settings
            var mutableCalibration = calibration

            let now = Date()
            let cal = Calendar.current
            let minuteKey = "\(cal.component(.year, from: now))-\(cal.component(.month, from: now))-\(cal.component(.day, from: now))-\(cal.component(.hour, from: now))-\(cal.component(.minute, from: now))"
            if minuteKey != lastScheduleMinuteKey {
                lastScheduleMinuteKey = minuteKey
                for action in scheduleUseCase.matchingActions(rules: mutableSettings.schedules, date: now, calendar: cal) {
                    switch action {
                    case .setLimit80:
                        mutableSettings.policy.limitPercent = VoltGuardLimits.defaultLimitPercent
                        mutableSettings.policy.topUpActive = false
                    case .topUp100:
                        mutableSettings.policy.topUpActive = true
                    case .enableDischarge:
                        mutableSettings.policy.manualDischarge = true
                    case .disableDischarge:
                        mutableSettings.policy.manualDischarge = false
                    }
                }
            }

            if mutableCalibration.isActive {
                mutableCalibration = calibrationUseCase.advance(
                    session: mutableCalibration,
                    telemetry: telemetry,
                    targetLimit: mutableSettings.policy.limitPercent,
                    now: now
                )
                mutableSettings.calibrationSession = mutableCalibration
            }

            let eval = policyUseCase.execute(
                telemetry: telemetry,
                policy: mutableSettings.policy,
                calibration: mutableCalibration,
                context: policyContext
            )
            policyContext = eval.updatedContext
            mutableSettings.policy = eval.updatedPolicy

            if mutableSettings != settings {
                settingsRepo.save(mutableSettings)
            }

            try? await smcGateway.applyCommand(eval.command)
            powerGateway.setPreventSleep(eval.command.preventSleepAssertion, reason: "VoltGuard active discharge or calibration")
            await powerGateway.setLowPowerMode(eval.command.lowPowerModeEnabled)

            emitTransitionAlerts(
                telemetry: telemetry,
                settings: mutableSettings,
                previousTopUp: settings.policy.topUpActive,
                newTopUp: mutableSettings.policy.topUpActive,
                previousCalibrationStage: calibration.stage,
                newCalibrationStage: mutableCalibration.stage,
                newReason: eval.command.statusReason
            )
            previousStatusReason = eval.command.statusReason

            let flow = powerFlowCalculator.calculate(from: telemetry)
            let snapshots = healthHistoryRepo.recordSnapshot(from: telemetry)
            onStateUpdate?(
                telemetry,
                flow,
                mutableSettings,
                mutableCalibration,
                eval.command.statusReason,
                smcGateway.isPrivilegedHelperConnected,
                snapshots,
                nil
            )
        } catch {
            onStateUpdate?(
                nil,
                PowerFlowMetrics(adapterInputWatts: 0, batteryNetWatts: 0, systemLoadWatts: 0),
                settings,
                calibration,
                .normalCharging,
                smcGateway.isPrivilegedHelperConnected,
                nil,
                error.localizedDescription
            )
        }
    }

    public func installHelper() async throws {
        try await smcGateway.installHelper()
    }

    public func uninstallHelper() async throws {
        try await smcGateway.uninstallHelper()
    }

    public func setLaunchAtLogin(_ enabled: Bool) throws {
        try launchAtLoginGateway.setEnabled(enabled)
    }

    public func requestAlertPermissions() {
        alertGateway.requestAuthorization()
    }

    public func loadHealthSnapshots() -> [BatteryHealthSnapshot] {
        healthHistoryRepo.loadSnapshots()
    }

    public func exportHealthCSV() -> String {
        healthHistoryRepo.exportCSV()
    }

    public func runDiagnostics(alertsEnabled: Bool) -> DiagnosticsReport {
        let iokitOK = (try? batteryReader.readTelemetry()) != nil
        return DiagnosticsReport(
            iokitReadable: iokitOK,
            smcHelperConnected: smcGateway.isPrivilegedHelperConnected,
            launchAtLoginEnabled: launchAtLoginGateway.isEnabled(),
            alertsEnabled: alertsEnabled
        )
    }

    private func emitTransitionAlerts(
        telemetry: BatteryTelemetry,
        settings: AppSettings,
        previousTopUp: Bool,
        newTopUp: Bool,
        previousCalibrationStage: CalibrationStage,
        newCalibrationStage: CalibrationStage,
        newReason: PolicyReason
    ) {
        guard settings.alertsEnabled else { return }
        let loc = settings.locale

        if newReason == .heatProtectionPaused && previousStatusReason != .heatProtectionPaused {
            alertGateway.sendAlert(
                id: "voltguard.heat",
                title: L10n.text(.alertHeatTitle, locale: loc),
                body: L10n.text(.alertHeatBody, locale: loc)
            )
        }
        if previousTopUp && !newTopUp {
            alertGateway.sendAlert(
                id: "voltguard.topup",
                title: L10n.text(.alertTopUpTitle, locale: loc),
                body: L10n.text(.alertTopUpBody, locale: loc)
            )
        }
        if previousCalibrationStage != .completed && newCalibrationStage == .completed {
            alertGateway.sendAlert(
                id: "voltguard.calibration",
                title: L10n.text(.alertCalibrationTitle, locale: loc),
                body: L10n.text(.alertCalibrationBody, locale: loc)
            )
        }
        if newReason == .limitReached && previousStatusReason == .normalCharging {
            alertGateway.sendAlert(
                id: "voltguard.limitreached",
                title: L10n.text(.alertLimitReachedTitle, locale: loc),
                body: L10n.text(.alertLimitReachedBody, locale: loc)
            )
        }
        if !telemetry.isPluggedIn && telemetry.percentage < VoltGuardLimits.lowBatteryAlertThresholdPercent {
            if !wasLowBatteryAlerted {
                wasLowBatteryAlerted = true
                alertGateway.sendAlert(
                    id: "voltguard.lowbattery",
                    title: L10n.text(.alertLowBatteryTitle, locale: loc),
                    body: L10n.text(.alertLowBatteryBody, locale: loc)
                )
            }
        } else if telemetry.isPluggedIn || telemetry.percentage >= VoltGuardLimits.lowBatteryAlertThresholdPercent + 5 {
            wasLowBatteryAlerted = false
        }
    }

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            self?.policyContext.isSystemSleeping = true
        }
        wakeObserver = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.policyContext.isSystemSleeping = false
        }
    }
}

@MainActor
public final class VoltGuardPresenter: ObservableObject {
    @Published public private(set) var state = VoltGuardViewState()

    private let interactor: VoltGuardInteractor
    private let recommendUseCase = RecommendProfileUseCase()
    private var etaCalculator = BatteryETACalculator()
    private var settingsObserver: NSObjectProtocol?
    private var toastDismissTask: Task<Void, Never>?
    public weak var router: AppRouterProtocol?

    public init(interactor: VoltGuardInteractor = VoltGuardInteractor()) {
        self.interactor = interactor
        let initial = interactor.loadInitialSettings()
        state.settings = initial
        state.calibration = initial.calibrationSession
        state.palette = ThemePalette.resolve(initial.theme)
        state.healthSnapshots = interactor.loadHealthSnapshots()

        interactor.onStateUpdate = { [weak self] telemetry, flow, settings, calibration, reason, helperConnected, snapshots, errMsg in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let prevReason = self.state.lastReason
                let prevTopUp = self.state.settings.policy.topUpActive
                let prevCalStage = self.state.calibration.stage
                if let telemetry {
                    self.state.telemetryState = .loaded(telemetry, flow)
                    self.state.liveRecommendation = self.recommendUseCase.recommend(
                        telemetry: telemetry,
                        currentPolicy: settings.policy
                    )
                    let displayWatts = flow.adapterInputWatts > 0 ? flow.adapterInputWatts : flow.systemLoadWatts
                    self.state.telemetryHistory = Self.appendSample(
                        TelemetrySample(watts: displayWatts, temperatureCelsius: telemetry.temperatureCelsius),
                        to: self.state.telemetryHistory
                    )
                    let isCalibratingToFull = calibration.isActive && calibration.stage == .chargingToFull
                    let targetLimit = (settings.policy.topUpActive || isCalibratingToFull)
                        ? VoltGuardLimits.maxLimitPercent
                        : settings.policy.limitPercent
                    self.state.batteryETA = self.etaCalculator.update(telemetry: telemetry, targetLimit: targetLimit)

                    if reason == .heatProtectionPaused && prevReason != .heatProtectionPaused {
                        self.appendActivity(.activityHeatPaused)
                        self.presentToolbarEvent(
                            ToolbarNotificationEvent(
                                icon: "thermometer.sun.fill",
                                titleKey: .alertHeatTitle,
                                bodyKey: .alertHeatBody,
                                severity: .danger,
                                actionTitleKey: .toastActionEnergyMonitor,
                                action: .openEnergyMonitor
                            )
                        )
                    } else if reason == .limitReached && prevReason == .normalCharging {
                        self.appendActivity(.activityLimitReached)
                        self.presentToolbarEvent(
                            ToolbarNotificationEvent(
                                icon: "bolt.horizontal.circle.fill",
                                titleKey: .statusLimitReached,
                                bodyKey: .alertLimitReachedBody,
                                severity: .accent,
                                actionTitleKey: .topUp,
                                action: .topUp100
                            )
                        )
                    } else if (reason == .manualDischarge || reason == .automaticDischarge)
                                && prevReason != .manualDischarge && prevReason != .automaticDischarge {
                        self.presentToolbarEvent(
                            ToolbarNotificationEvent(
                                icon: "arrow.down.circle.fill",
                                titleKey: .toastDischargeTitle,
                                bodyKey: .toastDischargeBody,
                                severity: .warning,
                                actionTitleKey: .toastActionStopDischarge,
                                action: .stopDischarge
                            )
                        )
                    }
                    if prevTopUp && !settings.policy.topUpActive {
                        self.appendActivity(.activityTopUpDone)
                        self.presentToolbarEvent(
                            ToolbarNotificationEvent(
                                icon: "checkmark.seal.fill",
                                titleKey: .alertTopUpTitle,
                                bodyKey: .alertTopUpBody,
                                severity: .accent,
                                actionTitleKey: .openFullApp,
                                action: .openFullApp
                            )
                        )
                    }
                    if prevCalStage != calibration.stage && calibration.stage != .idle {
                        if calibration.stage == .completed {
                            self.appendActivity(.activityCalibrationDone)
                            self.presentToolbarEvent(
                                ToolbarNotificationEvent(
                                    icon: "checkmark.seal.fill",
                                    titleKey: .alertCalibrationTitle,
                                    bodyKey: .alertCalibrationBody,
                                    severity: .accent,
                                    actionTitleKey: .toastActionViewProgress,
                                    action: .openCalibration
                                )
                            )
                        } else {
                            self.presentToolbarEvent(
                                ToolbarNotificationEvent(
                                    icon: "gauge.with.dots.needle.67percent",
                                    titleKey: .toastCalStageTitle,
                                    bodyKey: .toastCalStageBody,
                                    severity: .warning,
                                    actionTitleKey: .toastActionViewProgress,
                                    action: .openCalibration
                                )
                            )
                        }
                    }
                    if !telemetry.isPluggedIn && telemetry.percentage < VoltGuardLimits.lowBatteryAlertThresholdPercent {
                        if self.state.activityLog.first?.messageKey != .activityLowBattery {
                            self.appendActivity(.activityLowBattery)
                            self.presentToolbarEvent(
                                ToolbarNotificationEvent(
                                    icon: "battery.25",
                                    titleKey: .alertLowBatteryTitle,
                                    bodyKey: .alertLowBatteryBody,
                                    severity: .danger,
                                    actionTitleKey: .toastActionEnableLowPower,
                                    action: .enableLowPowerOnBattery
                                )
                            )
                        }
                    }
                } else if let errMsg {
                    self.state.telemetryState = .error(errMsg)
                }
                self.state.settings = settings
                self.state.calibration = calibration
                self.state.lastReason = reason
                self.state.helperConnected = helperConnected
                self.state.palette = ThemePalette.resolve(settings.theme)
                if let snapshots, snapshots != self.state.healthSnapshots {
                    self.state.healthSnapshots = snapshots
                }
            }
        }

        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(DataConstants.Storage.settingsChangedNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dispatch(.reloadSettingsFromDisk)
            }
        }

        startPolling(activePopover: false)
    }

    deinit {
        if let settingsObserver {
            DistributedNotificationCenter.default().removeObserver(settingsObserver)
        }
    }

    public func startPolling(activePopover: Bool) {
        state.isUIVisible = activePopover
        let interval = activePopover ? AppLayoutConstants.activePollingSeconds : AppLayoutConstants.backgroundPollingSeconds
        interactor.startPolling(intervalSeconds: interval) { [weak self] in
            guard let self else { return (AppSettings(), CalibrationSession()) }
            return (self.state.settings, self.state.calibration)
        }
    }

    public func dispatch(_ action: VoltGuardAction) {
        switch action {
        case .refreshTelemetry:
            Task { [weak self] in
                guard let self else { return }
                await self.interactor.tick(settings: self.state.settings, calibration: self.state.calibration)
            }
        case .refreshEnergyApps:
            state.energyState = .loading
            Task { [weak self] in
                guard let self else { return }
                do {
                    let apps = try await self.interactor.fetchTopEnergyApps()
                    self.state.energyState = .loaded(apps)
                } catch {
                    self.state.energyState = .error(error.localizedDescription)
                }
            }
        case .terminateEnergyApp(let pid):
            _ = interactor.terminateEnergyApp(pid: pid)
            dispatch(.refreshEnergyApps)
        case .applyProfileTier(let tier):
            state.settings.policy = recommendUseCase.policy(for: tier, preserving: state.settings.policy)
            if case .loaded(let telemetry, _) = state.telemetryState {
                state.liveRecommendation = recommendUseCase.recommend(
                    telemetry: telemetry,
                    currentPolicy: state.settings.policy
                )
            }
            persistAndSync()
        case .setChargeLimit(let limit):
            state.settings.policy.limitPercent = min(max(limit, VoltGuardLimits.minLimitPercent), VoltGuardLimits.maxLimitPercent)
            state.settings.policy.topUpActive = false
            persistAndSync()
        case .toggleManualDischarge:
            state.settings.policy.manualDischarge.toggle()
            persistAndSync()
        case .toggleAutomaticDischarge:
            state.settings.policy.automaticDischarge.toggle()
            persistAndSync()
        case .toggleClamshellDischarge:
            state.settings.policy.dischargeInClamshell.toggle()
            persistAndSync()
        case .toggleHeatProtection:
            state.settings.policy.heatProtectionEnabled.toggle()
            persistAndSync()
        case .setMaxTemperature(let temp):
            state.settings.policy.maxTemperatureCelsius = temp
            persistAndSync()
        case .toggleSailingMode:
            state.settings.policy.sailingModeEnabled.toggle()
            persistAndSync()
        case .setSailingDelta(let delta):
            state.settings.policy.sailingDeltaPercent = delta
            persistAndSync()
        case .setMagSafeLED(let mode):
            state.settings.policy.magSafeLEDMode = mode
            persistAndSync()
        case .toggleTopUp:
            state.settings.policy.topUpActive.toggle()
            persistAndSync()
        case .startCalibration:
            let session = CalibrationSession(
                stage: .chargingToFull,
                stageStartedAt: Date(),
                targetLowPercent: VoltGuardLimits.calibrationLowPercent,
                holdDurationSeconds: VoltGuardLimits.calibrationHoldSeconds
            )
            state.calibration = session
            state.settings.calibrationSession = session
            persistAndSync()
        case .stopCalibration:
            let session = CalibrationSession(stage: .idle)
            state.calibration = session
            state.settings.calibrationSession = session
            persistAndSync()
        case .toggleSleepControl:
            state.settings.policy.sleepControlEnabled.toggle()
            persistAndSync()
        case .toggleStopChargingOnSleep:
            state.settings.policy.stopChargingWhenSleeping.toggle()
            persistAndSync()
        case .toggleLowPowerOnBattery:
            state.settings.policy.lowPowerModeOnBattery.toggle()
            persistAndSync()
        case .toggleLowPowerAlways:
            state.settings.policy.lowPowerModeAlways.toggle()
            persistAndSync()
        case .addScheduleRule(let rule):
            state.settings.schedules.append(rule)
            persistAndSync()
        case .toggleScheduleRule(let id):
            if let idx = state.settings.schedules.firstIndex(where: { $0.id == id }) {
                state.settings.schedules[idx].isEnabled.toggle()
                persistAndSync()
            }
        case .removeScheduleRule(let id):
            state.settings.schedules.removeAll { $0.id == id }
            persistAndSync()
        case .updateTheme(let theme):
            state.settings.theme = theme
            state.palette = ThemePalette.resolve(theme)
            interactor.saveSettings(state.settings)
        case .updateLocale(let locale):
            state.settings.locale = locale
            interactor.saveSettings(state.settings)
        case .updateMenuBarConfig(let cfg):
            state.settings.menuBarIcon = cfg
            interactor.saveSettings(state.settings)
        case .updatePopoverLayout(let layout):
            state.settings.popoverLayout = layout
            interactor.saveSettings(state.settings)
        case .movePopoverModule(let module, let offset):
            var order = state.settings.popoverLayout.orderedModules
            guard let idx = order.firstIndex(of: module) else { return }
            let target = idx + offset
            guard target >= 0 && target < order.count else { return }
            order.swapAt(idx, target)
            state.settings.popoverLayout.orderedModules = order
            interactor.saveSettings(state.settings)
        case .exportHealthCSV:
            let csv = interactor.exportHealthCSV()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(csv, forType: .string)
            state.csvExportFeedback = true
        case .runDiagnostics:
            state.diagnostics = interactor.runDiagnostics(alertsEnabled: state.settings.alertsEnabled)
        case .toggleLaunchAtLogin:
            let next = !state.settings.launchAtLogin
            do {
                try interactor.setLaunchAtLogin(next)
                state.settings.launchAtLogin = next
                interactor.saveSettings(state.settings)
            } catch {
                state.helperErrorMessage = error.localizedDescription
            }
        case .toggleSmartAlerts:
            state.settings.alertsEnabled.toggle()
            if state.settings.alertsEnabled {
                interactor.requestAlertPermissions()
            }
            interactor.saveSettings(state.settings)
        case .saveCustomProfile:
            let policy = state.settings.policy
            state.settings.customProfile = CustomBatteryProfile(
                limitPercent: policy.limitPercent,
                sailingModeEnabled: policy.sailingModeEnabled,
                sailingDeltaPercent: policy.sailingDeltaPercent,
                maxTemperatureCelsius: policy.maxTemperatureCelsius
            )
            interactor.saveSettings(state.settings)
        case .applyCustomProfile:
            guard let custom = state.settings.customProfile else { return }
            state.settings.policy.limitPercent = custom.limitPercent
            state.settings.policy.sailingModeEnabled = custom.sailingModeEnabled
            state.settings.policy.sailingDeltaPercent = custom.sailingDeltaPercent
            state.settings.policy.maxTemperatureCelsius = custom.maxTemperatureCelsius
            state.settings.policy.topUpActive = false
            persistAndSync()
        case .exportSettingsJSON:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(state.settings), let json = String(data: data, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(json, forType: .string)
                state.settingsFeedbackMessage = L10n.text(.settingsSavedFeedback, locale: state.settings.locale)
            }
        case .importSettingsJSON(let json):
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                state.settingsFeedbackMessage = L10n.text(.settingsImportError, locale: state.settings.locale)
                return
            }
            state.settings = decoded
            state.palette = ThemePalette.resolve(decoded.theme)
            state.settingsFeedbackMessage = nil
            persistAndSync()
        case .resetSettingsToDefault:
            let currentLocale = state.settings.locale
            var defaults = AppSettings()
            defaults.locale = currentLocale
            state.settings = defaults
            state.palette = ThemePalette.resolve(defaults.theme)
            state.settingsFeedbackMessage = L10n.text(.settingsResetFeedback, locale: currentLocale)
            persistAndSync()
        case .reloadSettingsFromDisk:
            let reloaded = interactor.loadInitialSettings()
            state.settings = reloaded
            state.calibration = reloaded.calibrationSession
            state.palette = ThemePalette.resolve(reloaded.theme)
            dispatch(.refreshTelemetry)
        case .installHelper:
            state.helperErrorMessage = nil
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.interactor.installHelper()
                    await self.interactor.tick(settings: self.state.settings, calibration: self.state.calibration)
                } catch {
                    self.state.helperErrorMessage = error.localizedDescription
                }
            }
        case .uninstallHelper:
            state.helperErrorMessage = nil
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.interactor.uninstallHelper()
                    await self.interactor.tick(settings: self.state.settings, calibration: self.state.calibration)
                } catch {
                    self.state.helperErrorMessage = error.localizedDescription
                }
            }
        case .openFullApp:
            router?.openFullAppWindow()
        case .minimizeToBackground:
            router?.minimizeToBackground()
        case .hideMenuBarIcon:
            router?.setMenuBarIconVisible(false)
        case .dismissToolbarEvent:
            toastDismissTask?.cancel()
            state.activeToolbarEvent = nil
            router?.hideToolbarEventToast()
        case .triggerToolbarEventAction(let eventAction):
            toastDismissTask?.cancel()
            state.activeToolbarEvent = nil
            router?.hideToolbarEventToast()
            switch eventAction {
            case .topUp100:
                state.settings.policy.topUpActive = true
                persistAndSync()
            case .stopDischarge:
                state.settings.policy.manualDischarge = false
                state.settings.policy.automaticDischarge = false
                persistAndSync()
            case .enableLowPowerOnBattery:
                state.settings.policy.lowPowerModeOnBattery = true
                persistAndSync()
            case .openEnergyMonitor:
                state.requestedDashboardTab = 2
                router?.openFullAppWindow()
            case .openCalibration:
                state.requestedDashboardTab = 3
                router?.openFullAppWindow()
            case .openFullApp:
                router?.openFullAppWindow()
            }
        case .testToolbarEvent:
            presentToolbarEvent(
                ToolbarNotificationEvent(
                    icon: "bolt.horizontal.circle.fill",
                    titleKey: .statusLimitReached,
                    bodyKey: .alertLimitReachedBody,
                    severity: .accent,
                    actionTitleKey: .topUp,
                    action: .topUp100
                )
            )
        case .quitApp:
            NSApp.terminate(nil)
        }
    }

    public func presentToolbarEvent(_ event: ToolbarNotificationEvent) {
        guard state.settings.alertsEnabled else { return }
        toastDismissTask?.cancel()
        state.activeToolbarEvent = event
        router?.showToolbarEventToast()
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled, let self, self.state.activeToolbarEvent?.id == event.id else { return }
            self.state.activeToolbarEvent = nil
            self.router?.hideToolbarEventToast()
        }
    }

    private func appendActivity(_ key: L10nKey) {
        state.activityLog.insert(ActivityLogEntry(messageKey: key), at: 0)
        if state.activityLog.count > 20 {
            state.activityLog.removeLast(state.activityLog.count - 20)
        }
    }

    private func persistAndSync() {
        interactor.saveSettings(state.settings)
        Task { [weak self] in
            guard let self else { return }
            await self.interactor.tick(settings: self.state.settings, calibration: self.state.calibration)
        }
    }

    public static func appendSample(_ sample: TelemetrySample, to history: [TelemetrySample]) -> [TelemetrySample] {
        var next = history
        next.append(sample)
        if next.count > LiquidBatteryConstants.sparklineMaxSamples {
            next.removeFirst(next.count - LiquidBatteryConstants.sparklineMaxSamples)
        }
        return next
    }
}

@MainActor
public protocol AppRouterProtocol: AnyObject {
    func openFullAppWindow()
    func minimizeToBackground()
    func setMenuBarIconVisible(_ visible: Bool)
    func showToolbarEventToast()
    func hideToolbarEventToast()
}

public extension AppRouterProtocol {
    func showToolbarEventToast() {}
    func hideToolbarEventToast() {}
}
