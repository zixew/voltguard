import Foundation
import ServiceManagement
import UserNotifications
import VoltGuardDomain

public final class SystemLaunchAtLoginGateway: LaunchAtLoginGateway, @unchecked Sendable {
    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    public func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}

public final class SystemAlertNotificationGateway: NSObject, AlertNotificationGateway, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let actionNotificationName = Notification.Name("com.voltguard.systemNotificationAction")
    private let lock = NSLock()
    private var lastSentByIdentifier: [String: Date] = [:]
    private let cooldownSeconds: TimeInterval

    public init(cooldownSeconds: TimeInterval = 900) {
        self.cooldownSeconds = cooldownSeconds
        super.init()
        configureNotificationCenterIfPossible()
    }

    private var hasValidAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func configureNotificationCenterIfPossible() {
        guard hasValidAppBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let topUpAction = UNNotificationAction(identifier: "ACTION_TOP_UP", title: "Top Up 100%", options: [])
        let stopDischargeAction = UNNotificationAction(identifier: "ACTION_STOP_DISCHARGE", title: "Stop Discharge", options: [.destructive])
        let energyAction = UNNotificationAction(identifier: "ACTION_OPEN_ENERGY", title: "Energy Monitor", options: [.foreground])
        let lowPowerAction = UNNotificationAction(identifier: "ACTION_ENABLE_LOW_POWER", title: "Low Power Mode", options: [])
        let progressAction = UNNotificationAction(identifier: "ACTION_OPEN_CALIBRATION", title: "View Progress", options: [.foreground])

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: "VOLTGUARD_LIMIT", actions: [topUpAction], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "VOLTGUARD_HEAT", actions: [energyAction], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "VOLTGUARD_DISCHARGE", actions: [stopDischargeAction], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "VOLTGUARD_LOWBAT", actions: [lowPowerAction], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "VOLTGUARD_CALIBRATION", actions: [progressAction], intentIdentifiers: [], options: [])
        ]
        center.setNotificationCategories(categories)
    }

    public func requestAuthorization() {
        guard hasValidAppBundle else { return }
        configureNotificationCenterIfPossible()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func sendAlert(id: String, title: String, body: String) {
        let now = Date()
        let isManualTest = (id == "voltguard.test")
        if !isManualTest {
            let allowed = lock.withLock { () -> Bool in
                if let last = lastSentByIdentifier[id], now.timeIntervalSince(last) < cooldownSeconds {
                    return false
                }
                lastSentByIdentifier[id] = now
                return true
            }
            if !allowed { return }
        }

        guard hasValidAppBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "voltguard.power.events"
        content.categoryIdentifier = Self.categoryIdentifier(for: id)

        // Remove any previous banner with the same identifier so notifications replace in-place and never stack/spam.
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }

    private static func categoryIdentifier(for id: String) -> String {
        switch id {
        case "voltguard.limitreached", "voltguard.test": return "VOLTGUARD_LIMIT"
        case "voltguard.heat": return "VOLTGUARD_HEAT"
        case "voltguard.discharge": return "VOLTGUARD_DISCHARGE"
        case "voltguard.lowbattery": return "VOLTGUARD_LOWBAT"
        case "voltguard.calibration": return "VOLTGUARD_CALIBRATION"
        default: return "VOLTGUARD_DEFAULT"
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        NotificationCenter.default.post(
            name: Self.actionNotificationName,
            object: nil,
            userInfo: ["actionIdentifier": actionID, "notificationIdentifier": response.notification.request.identifier]
        )
        completionHandler()
    }
}
