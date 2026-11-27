import Foundation

public enum DataConstants {
    public enum Helper {
        public static let socketPath = "/var/run/voltguard-helper.sock"
        public static let installPath = "/Library/PrivilegedHelperTools/com.voltguard.helper"
        public static let plistPath = "/Library/LaunchDaemons/com.voltguard.helper.plist"
        public static let daemonLabel = "com.voltguard.helper"
        public static let bundleHelperRelativePath = "/Contents/Helpers/voltguard-helper"
        public static let executableName = "voltguard-helper"
    }

    public enum IOKit {
        public static let smartBatteryService = "AppleSmartBattery"
        public static let rootDomainService = "IOPMrootDomain"
        public static let clamshellProperty = "AppleClamshellState"
        public static let pmsetPath = "/usr/bin/pmset"
        public static let osascriptPath = "/usr/bin/osascript"
        public static let psPath = "/bin/ps"
    }

    public enum Storage {
        public static let appFolderName = "VoltGuard"
        public static let settingsFileName = "settings.json"
        public static let healthHistoryFileName = "health_history.json"
        public static let lockFileName = "voltguard.lock"
        public static let reopenNotificationName = "com.voltguard.reopen"
        public static let settingsChangedNotificationName = "com.voltguard.settingsChanged"
    }
}
