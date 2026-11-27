import AppIntents
import Foundation
import VoltGuardData
import VoltGuardDomain

private func saveAndNotify(_ settings: AppSettings, repo: JSONSettingsRepository) {
    repo.save(settings)
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(DataConstants.Storage.settingsChangedNotificationName),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

public struct SetChargeLimitIntent: AppIntent {
    public static var title: LocalizedStringResource = "Set VoltGuard Charge Limit"
    public static var description = IntentDescription("Sets the battery charge limit percentage (20 to 100).")

    @Parameter(title: "Limit Percent", default: 80)
    public var limitPercent: Int

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let repo = JSONSettingsRepository()
        var settings = repo.load()
        settings.policy.limitPercent = min(max(limitPercent, 20), 100)
        settings.policy.topUpActive = false
        saveAndNotify(settings, repo: repo)
        return .result(value: "VoltGuard limit set to \(settings.policy.limitPercent)%")
    }
}

public struct ToggleDischargeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle VoltGuard Discharge"
    public static var description = IntentDescription("Enables or disables manual battery discharge.")

    @Parameter(title: "Enabled", default: true)
    public var enabled: Bool

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let repo = JSONSettingsRepository()
        var settings = repo.load()
        settings.policy.manualDischarge = enabled
        saveAndNotify(settings, repo: repo)
        return .result(value: enabled ? "Discharge enabled" : "Discharge disabled")
    }
}

public struct StartTopUpIntent: AppIntent {
    public static var title: LocalizedStringResource = "Top Up Battery to 100%"
    public static var description = IntentDescription("Temporarily charges the battery to 100% and reverts to your saved limit.")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let repo = JSONSettingsRepository()
        var settings = repo.load()
        settings.policy.topUpActive = true
        saveAndNotify(settings, repo: repo)
        return .result(value: "Top Up active")
    }
}

public struct GetBatteryStatusIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get VoltGuard Battery Telemetry"
    public static var description = IntentDescription("Reads current battery percentage, temperature, and health.")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let reader = IOKitBatteryReader()
        let telemetry = try reader.readTelemetry()
        let summary = String(
            format: "Battery: %d%% | Temp: %.1fC | Health: %d%% (%@) | Cycles: %d",
            telemetry.percentage,
            telemetry.temperatureCelsius,
            telemetry.healthPercent,
            telemetry.batteryCondition.rawValue,
            telemetry.cycleCount
        )
        return .result(value: summary)
    }
}

public struct VoltGuardShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetChargeLimitIntent(),
            phrases: ["Set \(.applicationName) charge limit"],
            shortTitle: "Set Charge Limit",
            systemImageName: "battery.75percent"
        )
        AppShortcut(
            intent: StartTopUpIntent(),
            phrases: ["Top up battery with \(.applicationName)"],
            shortTitle: "Top Up 100%",
            systemImageName: "bolt.batteryblock"
        )
        AppShortcut(
            intent: GetBatteryStatusIntent(),
            phrases: ["Check battery health in \(.applicationName)"],
            shortTitle: "Battery Telemetry",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
    }
}
