import Foundation
import VoltGuardDomain

public enum AppUpdateError: Error, LocalizedError {
    case invalidResponse
    case downloadFailed
    case dmgMountFailed
    case appNotFoundInDMG
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unable to parse GitHub Releases response."
        case .downloadFailed: return "Failed to download VoltGuard.dmg update."
        case .dmgMountFailed: return "Failed to mount update DMG image."
        case .appNotFoundInDMG: return "VoltGuard.app was not found inside the downloaded DMG."
        case .installFailed(let msg): return "Update installation failed: \(msg)"
        }
    }
}

public final class AppUpdateService: Sendable {
    public init() {}

    public func checkLatestRelease() async throws -> AppUpdateCheckResult {
        guard let url = URL(string: AppReleaseInfo.latestReleaseAPI) else {
            throw AppUpdateError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VoltGuard/\(AppReleaseInfo.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppUpdateError.invalidResponse
        }

        let payload = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
        let latest = payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let dmgURL = payload.assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL
        let hasUpdate = AppReleaseInfo.isNewerVersion(latest, than: AppReleaseInfo.currentVersion)

        return AppUpdateCheckResult(
            currentVersion: AppReleaseInfo.currentVersion,
            latestVersion: latest,
            isUpdateAvailable: hasUpdate,
            releaseURL: payload.htmlURL,
            dmgDownloadURL: dmgURL,
            releaseNotes: payload.body ?? ""
        )
    }

    public func downloadAndInstall(dmgURLString: String) async throws {
        guard let url = URL(string: dmgURLString) else {
            throw AppUpdateError.downloadFailed
        }
        let (tempDMG, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppUpdateError.downloadFailed
        }

        let stagedDMG = FileManager.default.temporaryDirectory.appendingPathComponent("VoltGuard-Update-\(UUID().uuidString).dmg")
        try? FileManager.default.removeItem(at: stagedDMG)
        try FileManager.default.moveItem(at: tempDMG, to: stagedDMG)
        defer { try? FileManager.default.removeItem(at: stagedDMG) }

        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("voltguard-mount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
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

        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        relaunch.arguments = ["-n", destinationApp.path]
        try? relaunch.run()
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

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let assets: [GitHubAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

private struct GitHubAssetDTO: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
