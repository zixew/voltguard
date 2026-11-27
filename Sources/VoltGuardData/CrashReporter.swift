import Foundation

public struct CrashReport: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let buildMode: String
    public let appVersion: String
    public let osVersion: String
    public let type: String
    public let name: String
    public let reason: String
    public let callStack: [String]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        buildMode: String,
        appVersion: String,
        osVersion: String,
        type: String,
        name: String,
        reason: String,
        callStack: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.buildMode = buildMode
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.type = type
        self.name = name
        self.reason = reason
        self.callStack = callStack
    }
}

private final class SignalCrashContext {
    static let shared = SignalCrashContext()
    var crashFilePathBuffer: UnsafeMutablePointer<CChar>?
    var buildMode: String = "DEV"
    var previousHandlers: [Int32: sigaction] = [:]
}

private func voltGuardUncaughtExceptionHandler(_ exception: NSException) {
    CrashReporter.shared.recordException(
        name: exception.name.rawValue,
        reason: exception.reason ?? "Uncaught NSException",
        callStack: exception.callStackSymbols
    )
    CrashReporter.shared.markCleanExit()
}

private func voltGuardSignalHandler(_ signalCode: Int32) {
    if let pathPtr = SignalCrashContext.shared.crashFilePathBuffer {
        let fd = open(pathPtr, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 {
            let header = "SIGNAL=\(signalCode)\nMODE=\(SignalCrashContext.shared.buildMode)\n"
            header.withCString { ptr in
                _ = write(fd, ptr, strlen(ptr))
            }
            close(fd)
        }
    }

    var defaultAction = sigaction()
    defaultAction.__sigaction_u.__sa_handler = SIG_DFL
    sigemptyset(&defaultAction.sa_mask)
    sigaction(signalCode, &defaultAction, nil)
    raise(signalCode)
}

public final class CrashReporter: @unchecked Sendable {
    public static let shared = CrashReporter()

    public private(set) var crashesDirectoryURL: URL
    private var sessionMarkerURL: URL
    private let lock = NSLock()
    private var isInstalled = false

    public func configureDirectory(_ url: URL) {
        lock.withLock {
            self.crashesDirectoryURL = url
            self.sessionMarkerURL = url.appendingPathComponent(DataConstants.Storage.activeSessionMarkerName)
        }
    }

    public static var currentBuildMode: String {
        #if DEBUG
        return "DEV"
        #else
        return "RELEASE"
        #endif
    }

    public init(crashesDirectoryURL: URL? = nil) {
        if let customURL = crashesDirectoryURL {
            self.crashesDirectoryURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.crashesDirectoryURL = appSupport
                .appendingPathComponent(DataConstants.Storage.appFolderName, isDirectory: true)
                .appendingPathComponent(DataConstants.Storage.crashesFolderName, isDirectory: true)
        }
        self.sessionMarkerURL = self.crashesDirectoryURL
            .appendingPathComponent(DataConstants.Storage.activeSessionMarkerName)
    }

    public func install(registerProcessHandlers: Bool = true) {
        lock.withLock {
            try? FileManager.default.createDirectory(at: crashesDirectoryURL, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: sessionMarkerURL.path) {
                let markerInfo = (try? String(contentsOf: sessionMarkerURL, encoding: .utf8)) ?? "Previous session"
                let uncleanReport = CrashReport(
                    buildMode: Self.currentBuildMode,
                    appVersion: Self.appVersionString(),
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    type: "unclean_exit",
                    name: "UnexpectedTermination",
                    reason: "Previous session did not exit cleanly (\(markerInfo.trimmingCharacters(in: .whitespacesAndNewlines)))",
                    callStack: []
                )
                persistReportLocked(uncleanReport)
            }

            let pid = ProcessInfo.processInfo.processIdentifier
            let markerContent = "pid=\(pid) mode=\(Self.currentBuildMode) started=\(ISO8601DateFormatter().string(from: Date()))"
            try? markerContent.write(to: sessionMarkerURL, atomically: true, encoding: .utf8)

            guard registerProcessHandlers, !isInstalled else { return }
            isInstalled = true

            let signalFileURL = crashesDirectoryURL.appendingPathComponent("crash-\(Int(Date().timeIntervalSince1970)).signal.txt")
            if let oldPtr = SignalCrashContext.shared.crashFilePathBuffer {
                free(oldPtr)
            }
            SignalCrashContext.shared.crashFilePathBuffer = strdup(signalFileURL.path)
            SignalCrashContext.shared.buildMode = Self.currentBuildMode

            NSSetUncaughtExceptionHandler(voltGuardUncaughtExceptionHandler)

            let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP]
            for sig in signals {
                var action = sigaction()
                action.__sigaction_u.__sa_handler = voltGuardSignalHandler
                sigemptyset(&action.sa_mask)
                action.sa_flags = SA_RESETHAND
                var oldAction = sigaction()
                if sigaction(sig, &action, &oldAction) == 0 {
                    SignalCrashContext.shared.previousHandlers[sig] = oldAction
                }
            }
        }
    }

    public func markCleanExit() {
        lock.withLock {
            try? FileManager.default.removeItem(at: sessionMarkerURL)
        }
    }

    public func recordException(name: String, reason: String, callStack: [String]) {
        lock.withLock {
            try? FileManager.default.createDirectory(at: crashesDirectoryURL, withIntermediateDirectories: true)
            let report = CrashReport(
                buildMode: Self.currentBuildMode,
                appVersion: Self.appVersionString(),
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                type: "exception",
                name: name,
                reason: reason,
                callStack: callStack
            )
            persistReportLocked(report)
        }
    }

    public func loadReports() -> [CrashReport] {
        lock.withLock {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: crashesDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var reports: [CrashReport] = []
            for file in files {
                if file.lastPathComponent == DataConstants.Storage.activeSessionMarkerName {
                    continue
                }
                if file.pathExtension == "json",
                   let data = try? Data(contentsOf: file),
                   let report = try? decoder.decode(CrashReport.self, from: data) {
                    reports.append(report)
                } else if file.lastPathComponent.hasSuffix(".signal.txt"),
                          let text = try? String(contentsOf: file, encoding: .utf8) {
                    let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    let parsed = Self.parseSignalReport(text: text, fileName: file.lastPathComponent, date: modDate)
                    reports.append(parsed)
                }
            }

            return reports.sorted { $0.timestamp > $1.timestamp }
        }
    }

    public func latestReport() -> CrashReport? {
        loadReports().first
    }

    public func clearReports() {
        lock.withLock {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: crashesDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return
            }
            for file in files where file.lastPathComponent != DataConstants.Storage.activeSessionMarkerName {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func persistReportLocked(_ report: CrashReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        let fileName = "crash-\(Int(report.timestamp.timeIntervalSince1970))-\(report.id.prefix(8)).json"
        let targetURL = crashesDirectoryURL.appendingPathComponent(fileName)
        try? data.write(to: targetURL, options: [.atomic])
    }

    private static func parseSignalReport(text: String, fileName: String, date: Date) -> CrashReport {
        var signalValue = "Unknown"
        var mode = currentBuildMode
        for line in text.split(separator: "\n") {
            if line.hasPrefix("SIGNAL=") {
                signalValue = String(line.dropFirst("SIGNAL=".count))
            } else if line.hasPrefix("MODE=") {
                mode = String(line.dropFirst("MODE=".count))
            }
        }
        return CrashReport(
            id: fileName,
            timestamp: date,
            buildMode: mode,
            appVersion: appVersionString(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            type: "signal",
            name: "Signal(\(signalValue))",
            reason: "Process terminated by POSIX signal \(signalValue)",
            callStack: []
        )
    }

    private static func appVersionString() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
