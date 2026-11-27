import Foundation
import IOKit
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
    private let socketPath: String
    private let helperInstallPath = DataConstants.Helper.installPath
    private let plistPath = DataConstants.Helper.plistPath
    private let lock = NSLock()
    private var lastAppliedCommand: SMCCommandState?
    private var lastSocketReachable: Bool?
    private var lastBackendMode: SMCBackendMode = .unknown
    private var skippedIdenticalCount: Int = 0

    public init(socketPath: String = DataConstants.Helper.socketPath) {
        self.socketPath = socketPath
    }

    public var isPrivilegedHelperConnected: Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        if let known = lock.withLock({ lastSocketReachable }) {
            return known
        }
        return probeLiveConnection()
    }

    public var backendMode: SMCBackendMode {
        guard isPrivilegedHelperConnected else { return .unknown }
        if !isInstalledHelperUpToDate {
            return .outdatedHelper
        }
        return lock.withLock { lastBackendMode }
    }

    public var isInstalledHelperUpToDate: Bool {
        guard FileManager.default.fileExists(atPath: helperInstallPath),
              let bundledPath = locateBundledHelper(),
              let installedData = try? Data(contentsOf: URL(fileURLWithPath: helperInstallPath)),
              let bundledData = try? Data(contentsOf: URL(fileURLWithPath: bundledPath)) else {
            return false
        }
        return installedData == bundledData
    }

    public var isAppleSMCDriverReadable: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return false }
        defer { IOServiceClose(conn) }
        return true
    }

    public func probeLiveConnection() -> Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            lock.withLock {
                lastSocketReachable = false
                lastBackendMode = .unknown
            }
            return false
        }
        let pingPayload = HelperPayload(
            limitPercent: 80,
            allowCharging: true,
            forceDischarge: false,
            magSafeLED: "system",
            lowPowerModeEnabled: false,
            pingOnly: true
        )
        guard let data = try? JSONEncoder().encode(pingPayload),
              let ack = try? sendToSocket(data) else {
            lock.withLock {
                lastSocketReachable = false
                lastBackendMode = .unknown
            }
            return false
        }
        lock.withLock {
            lastSocketReachable = true
            lastBackendMode = ack
        }
        return true
    }

    public func restoreDefaultChargingSync() {
        guard FileManager.default.fileExists(atPath: socketPath) else { return }
        let payload = HelperPayload(
            limitPercent: 100,
            allowCharging: true,
            forceDischarge: false,
            magSafeLED: "system",
            lowPowerModeEnabled: false,
            pingOnly: false
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        _ = try? sendToSocket(data)
    }

    public func applyCommand(_ command: SMCCommandState) async throws {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            lock.withLock {
                lastAppliedCommand = nil
                lastSocketReachable = false
                skippedIdenticalCount = 0
            }
            return
        }

        // Re-assert SMC/ACLC every 3rd poll even when command is unchanged so macOS powerd cannot silently reset LED color.
        let shouldSkip = lock.withLock { () -> Bool in
            if lastSocketReachable == true && lastAppliedCommand == command {
                skippedIdenticalCount += 1
                if skippedIdenticalCount < 3 {
                    return true
                }
            }
            skippedIdenticalCount = 0
            return false
        }
        if shouldSkip { return }

        let payload = HelperPayload(
            limitPercent: command.targetLimitPercent,
            allowCharging: command.allowCharging,
            forceDischarge: command.forceDischarge,
            magSafeLED: command.magSafeLED.rawValue,
            lowPowerModeEnabled: command.lowPowerModeEnabled,
            pingOnly: false
        )
        let data = try JSONEncoder().encode(payload)
        do {
            let detectedMode = try sendToSocket(data)
            lock.withLock {
                lastSocketReachable = true
                lastBackendMode = detectedMode
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
        launchctl bootout system/\(DataConstants.Helper.daemonLabel) 2>/dev/null || launchctl unload '\(plistPath)' 2>/dev/null || true && \
        launchctl bootstrap system '\(plistPath)' 2>/dev/null || launchctl load -w '\(plistPath)' && \
        launchctl kickstart -k system/\(DataConstants.Helper.daemonLabel) 2>/dev/null || true
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
                proc.terminationHandler = nil
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                try? errorPipe.fileHandleForReading.close()
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
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

    private func openConnectedSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SMCHelperError.socketWriteFailed }

        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
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
        guard connectResult == 0 else {
            close(fd)
            throw SMCHelperError.socketWriteFailed
        }
        return fd
    }

    @discardableResult
    private func sendToSocket(_ data: Data) throws -> SMCBackendMode {
        var lineData = data
        lineData.append(0x0A)

        for attempt in 0..<2 {
            let fd = try openConnectedSocket()
            let sent = lineData.withUnsafeBytes { buf in
                write(fd, buf.baseAddress!, lineData.count)
            }
            let writeErrno = errno

            if sent == lineData.count {
                var ackBuffer = [UInt8](repeating: 0, count: 1024)
                let readCount = read(fd, &ackBuffer, ackBuffer.count)
                close(fd)

                if readCount > 0 {
                    let ackData = Data(ackBuffer.prefix(readCount))
                    if let ack = try? JSONDecoder().decode(HelperAckPayload.self, from: ackData) {
                        return SMCBackendMode(rawValue: ack.backendMode) ?? .unknown
                    }
                }
                return .outdatedHelper
            }

            close(fd)
            let transientError = (writeErrno == EPIPE || writeErrno == ECONNRESET)
            if attempt == 0 && transientError {
                continue
            }
            throw SMCHelperError.socketWriteFailed
        }
        throw SMCHelperError.socketWriteFailed
    }
}

private struct HelperPayload: Encodable {
    let limitPercent: Int
    let allowCharging: Bool
    let forceDischarge: Bool
    let magSafeLED: String
    let lowPowerModeEnabled: Bool
    let pingOnly: Bool?
}

private struct HelperAckPayload: Decodable {
    let ok: Bool
    let backendMode: String
}
