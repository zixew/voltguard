import Foundation

public struct SMCCommandState: Equatable, Sendable {
    public let targetLimitPercent: Int
    public let allowCharging: Bool
    public let forceDischarge: Bool
    public let preventSleepAssertion: Bool
    public let magSafeLED: MagSafeLEDMode
    public let lowPowerModeEnabled: Bool
    public let statusReason: PolicyReason

    public init(
        targetLimitPercent: Int,
        allowCharging: Bool,
        forceDischarge: Bool,
        preventSleepAssertion: Bool,
        magSafeLED: MagSafeLEDMode,
        lowPowerModeEnabled: Bool,
        statusReason: PolicyReason
    ) {
        self.targetLimitPercent = targetLimitPercent
        self.allowCharging = allowCharging
        self.forceDischarge = forceDischarge
        self.preventSleepAssertion = preventSleepAssertion
        self.magSafeLED = magSafeLED
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.statusReason = statusReason
    }
}

public enum PolicyReason: String, Equatable, Sendable {
    case normalCharging
    case limitReached
    case sailingPaused
    case heatProtectionPaused
    case manualDischarge
    case automaticDischarge
    case topUpActive
    case calibrationActive
    case sleepingInhibited
}

public protocol BatteryReadingGateway: Sendable {
    func readTelemetry() throws -> BatteryTelemetry
}

public protocol SMCControlGateway: Sendable {
    var isPrivilegedHelperConnected: Bool { get }
    var isInstalledHelperUpToDate: Bool { get }
    var isAppleSMCDriverReadable: Bool { get }
    var backendMode: SMCBackendMode { get }
    var writableKeys: [String] { get }
    var helperVersionSignature: String { get }
    func probeLiveConnection() -> Bool
    func applyCommand(_ command: SMCCommandState) async throws
    func restoreDefaultChargingSync()
    func installHelper() async throws
    func uninstallHelper() async throws
}

public extension SMCControlGateway {
    var isInstalledHelperUpToDate: Bool { isPrivilegedHelperConnected }
    var isAppleSMCDriverReadable: Bool { true }
    var backendMode: SMCBackendMode { .unknown }
    var writableKeys: [String] { [] }
    var helperVersionSignature: String { isPrivilegedHelperConnected ? "connected" : "dry-run" }
    func probeLiveConnection() -> Bool { isPrivilegedHelperConnected }
    func restoreDefaultChargingSync() {}
}

public protocol PowerManagementGateway: Sendable {
    func setPreventSleep(_ prevent: Bool, reason: String)
    func setLowPowerMode(_ enabled: Bool) async
}

public protocol SettingsRepository: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public protocol LaunchAtLoginGateway: Sendable {
    func setEnabled(_ enabled: Bool) throws
    func isEnabled() -> Bool
}

public protocol AlertNotificationGateway: Sendable {
    func requestAuthorization()
    func sendAlert(id: String, title: String, body: String)
}
