import Foundation
import VoltGuardDomain

public enum SMCHelperError: Error, LocalizedError {
    case helperBinaryMissing
    case installationCancelled(String)
    case socketWriteFailed

    public var errorDescription: String? {
        switch self {
        case .helperBinaryMissing:
            return "Privileged helper binary was not found in the app bundle."
        case .installationCancelled(let detail):
            return "Helper installation failed: \(detail)"
        case .socketWriteFailed:
            return "Failed to send command to voltguard-helper."
        }
    }
}

public final class DualModeSMCGateway: SMCControlGateway, @unchecked Sendable {
    private let socketPath = DataConstants.Helper.socketPath
    private let helperInstallPath = DataConstants.Helper.installPath
    private let plistPath = DataConstants.Helper.plistPath
    private let lock = NSLock()
    private var lastAppliedCommand: SMCCommandState?
    private var lastSocketReachable: Bool?

    public init() {}

    public var isPrivilegedHelperConnected: Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        return lock.withLock { lastSocketReachable ?? true }
    }

    public func applyCommand(_ command: SMCCommandState) async throws {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            lock.withLock {
                lastAppliedCommand = nil
                lastSocketReachable = false
            }
            return
        }

        let unchanged = lock.withLock {
            lastSocketReachable == true && lastAppliedCommand == command
        }
        if unchanged { return }

        let payload = HelperPayload(
            limitPercent: command.targetLimitPercent,
            allowCharging: command.allowCharging,
            forceDischarge: command.forceDischarge,
            magSafeLED: command.magSafeLED.rawValue,
            lowPowerModeEnabled: command.lowPowerModeEnabled
        )
        let data = try JSONEncoder().encode(payload)
        do {
            try sendToSocket(data)
            lock.withLock {
                lastSocketReachable = true
                lastAppliedCommand = command
            }
        } catch {
            lock.withLock {
                lastSocketReachable = false
                lastAppliedCommand = nil
            }
            throw error
        }
    }

    public func installHelper() async throws {
        guard let bundledHelper = locateBundledHelper() else {
            throw SMCHelperError.helperBinaryMissing
        }

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.voltguard.helper</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperInstallPath)</string>
                <string>--daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """

        let tempPlist = NSTemporaryDirectory() + "com.voltguard.helper.plist"
        try plistContent.write(toFile: tempPlist, atomically: true, encoding: .utf8)

        let shellCmd = """
        mkdir -p /Library/PrivilegedHelperTools && \
        cp '\(bundledHelper)' '\(helperInstallPath)' && \
        chmod 755 '\(helperInstallPath)' && \
        chown root:wheel '\(helperInstallPath)' && \
        cp '\(tempPlist)' '\(plistPath)' && \
        chmod 644 '\(plistPath)' && \
        chown root:wheel '\(plistPath)' && \
        launchctl unload '\(plistPath)' 2>/dev/null || true && \
        launchctl load -w '\(plistPath)'
        """

        do {
            try await runAdminScript(shellCmd)
            try? FileManager.default.removeItem(atPath: tempPlist)
            lock.withLock {
                lastSocketReachable = nil
                lastAppliedCommand = nil
            }
        } catch {
            try? FileManager.default.removeItem(atPath: tempPlist)
            throw error
        }
    }

    public func uninstallHelper() async throws {
        let shellCmd = """
        launchctl unload '\(plistPath)' 2>/dev/null || true && \
        rm -f '\(plistPath)' '\(helperInstallPath)' '\(socketPath)'
        """
        try await runAdminScript(shellCmd)
        lock.withLock {
            lastSocketReachable = false
            lastAppliedCommand = nil
        }
    }

    private func runAdminScript(_ shellCmd: String) async throws {
        let appleScript = "do shell script \"\(shellCmd.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: DataConstants.IOKit.osascriptPath)
            process.arguments = ["-e", appleScript]

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown authorization error"
                    continuation.resume(throwing: SMCHelperError.installationCancelled(errMsg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func locateBundledHelper() -> String? {
        if let helperURL = Bundle.main.url(forAuxiliaryExecutable: "voltguard-helper") {
            return helperURL.path
        }
        let bundleHelpers = Bundle.main.bundlePath + "/Contents/Helpers/voltguard-helper"
        if FileManager.default.fileExists(atPath: bundleHelpers) {
            return bundleHelpers
        }
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("voltguard-helper").path
        if FileManager.default.fileExists(atPath: sibling) {
            return sibling
        }
        return nil
    }

    private func sendToSocket(_ data: Data) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SMCHelperError.socketWriteFailed }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw SMCHelperError.socketWriteFailed
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                _ = pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, addrLen)
            }
        }
        guard connectResult == 0 else { throw SMCHelperError.socketWriteFailed }

        var lineData = data
        lineData.append(0x0A)
        let sent = lineData.withUnsafeBytes { buf in
            write(fd, buf.baseAddress!, lineData.count)
        }
        guard sent == lineData.count else { throw SMCHelperError.socketWriteFailed }
    }
}

private struct HelperPayload: Encodable {
    let limitPercent: Int
    let allowCharging: Bool
    let forceDischarge: Bool
    let magSafeLED: String
    let lowPowerModeEnabled: Bool
}
