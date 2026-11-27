import AppKit
import Foundation
import VoltGuardDomain

public enum EnergyMonitorError: Error, LocalizedError {
    case processFailed

    public var errorDescription: String? {
        "Unable to sample running processes."
    }
}

public final class SystemEnergyMonitor: EnergyMonitorGateway, @unchecked Sendable {
    public init() {}

    public func fetchTopEnergyApps(limit: Int) async throws -> [EnergyAppUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: DataConstants.IOKit.psPath)
        process.arguments = ["-axo", "pid=,pcpu=,comm="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try? pipe.fileHandleForReading.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            throw EnergyMonitorError.processFailed
        }

        let runningApps = await MainActor.run {
            var map: [Int32: (String, String?)] = [:]
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                let name = app.localizedName ?? app.bundleIdentifier ?? "App"
                map[app.processIdentifier] = (name, app.bundleIdentifier)
            }
            return map
        }

        return Self.parsePSOutput(
            output,
            runningAppMetadata: runningApps,
            excludedPID: ProcessInfo.processInfo.processIdentifier,
            limit: limit
        )
    }

    @MainActor
    public func terminateApp(pid: Int32) -> Bool {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.terminate()
    }

    public static func parsePSOutput(
        _ output: String,
        runningAppMetadata: [Int32: (String, String?)] = [:],
        excludedPID: Int32 = -1,
        limit: Int = 12
    ) -> [EnergyAppUsage] {
        var usages: [EnergyAppUsage] = []

        for rawLine in output.split(separator: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  pid != excludedPID else {
                continue
            }

            let commandPath = String(parts[2])
            let fallbackName = URL(fileURLWithPath: commandPath).lastPathComponent
            if let meta = runningAppMetadata[pid] {
                usages.append(EnergyAppUsage(pid: pid, name: meta.0, bundleIdentifier: meta.1, cpuPercent: cpu))
            } else if runningAppMetadata.isEmpty && cpu >= 0.5 {
                usages.append(EnergyAppUsage(pid: pid, name: fallbackName, bundleIdentifier: nil, cpuPercent: cpu))
            }
        }

        return usages
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(max(limit, 1))
            .map { $0 }
    }
}
