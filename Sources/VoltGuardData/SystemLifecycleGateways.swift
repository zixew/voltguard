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

public final class SystemAlertNotificationGateway: AlertNotificationGateway, @unchecked Sendable {
    public init() {}

    private var hasValidAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public func requestAuthorization() {
        guard hasValidAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func sendAlert(id: String, title: String, body: String) {
        guard hasValidAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
