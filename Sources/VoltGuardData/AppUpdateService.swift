import Foundation
import VoltGuardDomain

public enum AppUpdateError: Error, LocalizedError {
    case serviceUnavailable(Int)
    case invalidResponse
    case downloadFailed
    case dmgMountFailed
    case appNotFoundInDMG
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable(let code): return "Update service unavailable (HTTP \(code))."
        case .invalidResponse: return "Unable to verify update manifest."
        case .downloadFailed: return "Failed to download the latest VoltGuard installer."
        case .dmgMountFailed: return "Failed to open the downloaded installer package."
        case .appNotFoundInDMG: return "VoltGuard.app was not found inside the downloaded installer."
        case .installFailed(let msg): return "Update installation failed: \(msg)"
        }
    }
}

public final class AppUpdateService: Sendable {
    public init() {}

    public func checkLatestRelease() async throws -> AppUpdateCheckResult {
        guard let url = URL(string: AppReleaseInfo.feedURL) else {
            throw AppUpdateError.invalidResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VoltGuard/\(AppReleaseInfo.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppUpdateError.serviceUnavailable(http.statusCode)
        }
        return try Self.decodeAppcast(data: data)
    }

    public static func decodeAppcast(data: Data) throws -> AppUpdateCheckResult {
        let payload = try JSONDecoder().decode(AppcastFeedDTO.self, from: data)
        let latest = payload.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let hasUpdate = AppReleaseInfo.isNewerVersion(latest, than: AppReleaseInfo.currentVersion)

        return AppUpdateCheckResult(
            currentVersion: AppReleaseInfo.currentVersion,
            latestVersion: latest,
            latestBuild: payload.build,
            publishedAt: payload.publishedAt,
            isUpdateAvailable: hasUpdate,
            dmgDownloadURL: payload.dmgURL,
            latestChangesEN: payload.changesEN,
            latestFixesEN: payload.fixesEN,
            latestChangesID: payload.changesID,
            latestFixesID: payload.fixesID
        )
    }

    public func downloadAndInstall(
        dmgURLString: String,
        onStage: @escaping @Sendable (AppUpdateStage) -> Void
    ) async throws {
        guard let url = URL(string: dmgURLString) else {
            throw AppUpdateError.downloadFailed
        }

        await MainActor.run { onStage(.downloading(0.02)) }
        let tempDMG = try await downloadWithProgress(url: url, onProgress: { fraction in
            Task { @MainActor in onStage(.downloading(fraction)) }
        })

        let stagedDMG = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoltGuard-Update-\(UUID().uuidString).dmg")
        try? FileManager.default.removeItem(at: stagedDMG)
        try FileManager.default.moveItem(at: tempDMG, to: stagedDMG)
        defer { Self.cleanupDMGArtifacts(at: [stagedDMG]) }

        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("voltguard-mount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        await MainActor.run { onStage(.installing) }
        let useDiskUtil = Self.supportsModernDiskUtilImage()
        defer {
            let detach = Process()
            if useDiskUtil {
                detach.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                detach.arguments = ["unmount", "force", mountPoint.path]
            } else {
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
            }
            try? detach.run()
            detach.waitUntilExit()
            try? FileManager.default.removeItem(at: mountPoint)
        }

        let attach = Process()
        if useDiskUtil {
            attach.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            attach.arguments = ["image", "attach", "--nobrowse", "--mountPoint", mountPoint.path, stagedDMG.path]
        } else {
            attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            attach.arguments = ["attach", stagedDMG.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
        }
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else {
            throw AppUpdateError.dmgMountFailed
        }

        let sourceApp = mountPoint.appendingPathComponent("VoltGuard.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw AppUpdateError.appNotFoundInDMG
        }

        let destinationApp = URL(fileURLWithPath: "/Applications/VoltGuard.app")
        if FileManager.default.isWritableFile(atPath: "/Applications") {
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/sh")
            swap.arguments = ["-c", "rm -rf '/Applications/VoltGuard.app' && cp -R '\(sourceApp.path)' '/Applications/VoltGuard.app'"]
            try swap.run()
            swap.waitUntilExit()
            guard swap.terminationStatus == 0 else {
                throw AppUpdateError.installFailed("Copy to /Applications returned \(swap.terminationStatus)")
            }
        } else {
            let cmd = "rm -rf '/Applications/VoltGuard.app' && cp -R '\(sourceApp.path)' '/Applications/VoltGuard.app'"
            let appleScript = "do shell script \"\(cmd.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
            let osa = Process()
            osa.executableURL = URL(fileURLWithPath: DataConstants.IOKit.osascriptPath)
            osa.arguments = ["-e", appleScript]
            try osa.run()
            osa.waitUntilExit()
            guard osa.terminationStatus == 0 else {
                throw AppUpdateError.installFailed("Administrator authorization cancelled.")
            }
        }

        await MainActor.run { onStage(.cleaningUp) }
        Self.cleanupDMGArtifacts(at: [stagedDMG])
        Self.cleanupDownloadedVoltGuardDMGs()
        await MainActor.run { onStage(.completed) }

        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        relaunch.arguments = ["-n", destinationApp.path]
        try? relaunch.run()
    }

    public static func cleanupDMGArtifacts(at urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func cleanupDownloadedVoltGuardDMGs() {
        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              let entries = try? FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil) else {
            return
        }
        let matching = entries.filter {
            let name = $0.lastPathComponent.lowercased()
            return name.hasPrefix("voltguard") && name.hasSuffix(".dmg")
        }
        cleanupDMGArtifacts(at: matching)
    }

    private func downloadWithProgress(
        url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let onProgress: @Sendable (Double) -> Void
            private let lock = NSLock()
            private var continuation: CheckedContinuation<(URL, URLResponse), Error>?

            init(onProgress: @escaping @Sendable (Double) -> Void) {
                self.onProgress = onProgress
            }

            func setContinuation(_ cont: CheckedContinuation<(URL, URLResponse), Error>) {
                lock.lock()
                continuation = cont
                lock.unlock()
            }

            private func takeContinuation() -> CheckedContinuation<(URL, URLResponse), Error>? {
                lock.lock()
                let cont = continuation
                continuation = nil
                lock.unlock()
                return cont
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didWriteData bytesWritten: Int64,
                totalBytesWritten: Int64,
                totalBytesExpectedToWrite: Int64
            ) {
                guard totalBytesExpectedToWrite > 0 else { return }
                let ratio = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.02), 0.99)
                onProgress(ratio)
            }

            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                guard let cont = takeContinuation() else { return }
                let copyURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("voltguard-dl-\(UUID().uuidString).dmg")
                do {
                    try? FileManager.default.removeItem(at: copyURL)
                    try FileManager.default.copyItem(at: location, to: copyURL)
                    let resp = downloadTask.response ?? URLResponse()
                    cont.resume(returning: (copyURL, resp))
                } catch {
                    cont.resume(throwing: error)
                }
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error, let cont = takeContinuation() {
                    cont.resume(throwing: error)
                }
            }
        }

        let delegate = ProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempFile, response): (URL, URLResponse) = try await withCheckedThrowingContinuation { cont in
            delegate.setContinuation(cont)
            let task = session.downloadTask(with: url)
            task.resume()
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempFile)
            throw AppUpdateError.downloadFailed
        }
        return tempFile
    }

    private static func supportsModernDiskUtilImage() -> Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        probe.arguments = ["image", "--help"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private struct AppcastFeedDTO: Decodable {
    let version: String
    let build: String
    let publishedAt: String
    let dmgURL: String
    let changesEN: [String]
    let fixesEN: [String]
    let changesID: [String]
    let fixesID: [String]
}
