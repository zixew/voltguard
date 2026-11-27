import Foundation

struct HelperCommand: Decodable {
    let limitPercent: Int
    let allowCharging: Bool
    let forceDischarge: Bool
    let magSafeLED: String
    let lowPowerModeEnabled: Bool?
    let pingOnly: Bool?
}

struct HelperAck: Encodable {
    let ok: Bool
    let backendMode: String
    let writableKeys: [String]
}

struct SMCCapabilities {
    let hasFirmwareLimitKeys: Bool
    let hasLegacyChargePair: Bool
    let hasTahoeChargeKey: Bool
    let hasBCLM: Bool
    let adapterKey: (key: String, cutValue: UInt8)?
    let hasACLC: Bool

    init(client: SMCClient) {
        self.hasFirmwareLimitKeys = client.isKeyWritable("bfF0", verifyWrite: true)
            && client.isKeyWritable("bfD0", verifyWrite: true)
            && client.isKeyWritable("bfE0", verifyWrite: true)
        self.hasTahoeChargeKey = client.isKeyWritable("CHTE", verifyWrite: true)
        self.hasLegacyChargePair = client.isKeyWritable("CH0B", verifyWrite: true)
            && client.isKeyWritable("CH0C", verifyWrite: true)
        self.hasBCLM = client.isKeyWritable("BCLM", verifyWrite: true)
        self.hasACLC = client.isKeyWritable("ACLC", verifyWrite: true)

        if client.isKeyWritable("CHIE", verifyWrite: true) {
            self.adapterKey = ("CHIE", 0x08)
        } else if client.isKeyWritable("CH0I", verifyWrite: true) {
            self.adapterKey = ("CH0I", 0x01)
        } else if client.isKeyWritable("CH0J", verifyWrite: true) {
            self.adapterKey = ("CH0J", 0x01)
        } else if client.isKeyWritable("CH0K", verifyWrite: true) {
            self.adapterKey = ("CH0K", 0x01)
        } else {
            self.adapterKey = nil
        }
    }

    var backendMode: String {
        if hasFirmwareLimitKeys {
            return "firmwareManaged"
        }
        if hasLegacyChargePair || hasTahoeChargeKey || hasBCLM {
            return "legacy"
        }
        if adapterKey != nil {
            return "adapterMode"
        }
        return "unsupported"
    }

    var writableKeyList: [String] {
        var keys: [String] = []
        if hasFirmwareLimitKeys { keys.append(contentsOf: ["bfF0", "bfD0", "bfE0"]) }
        if hasLegacyChargePair { keys.append(contentsOf: ["CH0B", "CH0C"]) }
        if hasTahoeChargeKey { keys.append("CHTE") }
        if hasBCLM { keys.append("BCLM") }
        if let adapterKey { keys.append(adapterKey.key) }
        if hasACLC { keys.append("ACLC") }
        return keys
    }
}

let socketPath: String = {
    if let idx = CommandLine.arguments.firstIndex(of: "--socket"), idx + 1 < CommandLine.arguments.count {
        return CommandLine.arguments[idx + 1]
    }
    return "/var/run/voltguard-helper.sock"
}()
var lastAppliedLowPower: Bool?

func applyLowPowerModeIfNeeded(_ enabled: Bool?) {
    guard let enabled, enabled != lastAppliedLowPower else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-a", "lowpowermode", enabled ? "1" : "0"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    if (try? process.run()) != nil {
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            lastAppliedLowPower = enabled
        }
    }
}

@discardableResult
func applySMC(_ cmd: HelperCommand, client: SMCClient, caps: SMCCapabilities, resolvedMode: inout String) -> Bool {
    let clamped = min(max(cmd.limitPercent, 20), 100)
    var success = true
    resolvedMode = caps.backendMode

    switch caps.backendMode {
    case "firmwareManaged":
        if cmd.forceDischarge {
            _ = client.writeByte(key: "bfF0", value: 0x00)
            if let adapter = caps.adapterKey {
                success = client.writeByte(key: adapter.key, value: adapter.cutValue) && success
            } else {
                success = false
            }
        } else {
            if let adapter = caps.adapterKey {
                _ = client.writeByte(key: adapter.key, value: 0x00)
            }
            if !cmd.allowCharging && clamped == 100 {
                success = client.writeByte(key: "bfF0", value: 0x00) && success
            } else if clamped < 100 {
                let lower = UInt32(max(clamped - 5, 15))
                _ = client.writeByte(key: "bfF0", value: 0x00)
                success = client.writeUInt32BigEndian(key: "bfD0", value: UInt32(clamped)) && success
                success = client.writeUInt32BigEndian(key: "bfE0", value: lower) && success
                success = client.writeByte(key: "bfF0", value: 0x02) && success
                if !success, let adapter = caps.adapterKey {
                    success = client.writeByte(key: adapter.key, value: adapter.cutValue)
                    if success { resolvedMode = "adapterMode" }
                }
            } else {
                _ = client.writeByte(key: "bfF0", value: 0x00)
            }
        }

    case "legacy":
        var bclmOK = false
        if caps.hasBCLM {
            bclmOK = client.writeByte(key: "BCLM", value: UInt8(clamped))
        }
        if cmd.forceDischarge {
            if let adapter = caps.adapterKey {
                success = client.writeByte(key: adapter.key, value: adapter.cutValue) && success
            } else {
                success = false
            }
            if caps.hasTahoeChargeKey {
                _ = client.writeBytes(key: "CHTE", values: [0x01, 0x00, 0x00, 0x00])
            } else if caps.hasLegacyChargePair {
                _ = client.writeByte(key: "CH0B", value: 2)
                _ = client.writeByte(key: "CH0C", value: 2)
            }
        } else if !cmd.allowCharging {
            if let adapter = caps.adapterKey {
                _ = client.writeByte(key: adapter.key, value: 0x00)
            }
            var inhibitOK = false
            if caps.hasTahoeChargeKey {
                inhibitOK = client.writeBytes(key: "CHTE", values: [0x01, 0x00, 0x00, 0x00])
            }
            if !inhibitOK && caps.hasLegacyChargePair {
                let b = client.writeByte(key: "CH0B", value: 2)
                let c = client.writeByte(key: "CH0C", value: 2)
                inhibitOK = b && c
            }
            if !inhibitOK && caps.hasBCLM {
                inhibitOK = bclmOK
            }
            if !inhibitOK, let adapter = caps.adapterKey {
                // Runtime fallback when firmware rejects primary charge-inhibit keys.
                inhibitOK = client.writeByte(key: adapter.key, value: adapter.cutValue)
                if inhibitOK { resolvedMode = "adapterMode" }
            }
            success = inhibitOK
        } else {
            if let adapter = caps.adapterKey {
                _ = client.writeByte(key: adapter.key, value: 0x00)
            }
            if caps.hasTahoeChargeKey {
                _ = client.writeBytes(key: "CHTE", values: [0x00, 0x00, 0x00, 0x00])
            }
            if caps.hasLegacyChargePair {
                _ = client.writeByte(key: "CH0B", value: 0)
                _ = client.writeByte(key: "CH0C", value: 0)
            }
        }

    case "adapterMode":
        // macOS 27 (20457.0.125.0.2+): charge-inhibit keys (CH0B/CH0C/CHTE/bfF0) are entitlement-gated.
        // Adapter cut key (CHIE=0x08 / CH0I=0x01 / CH0K=0x01) remains writable and stops charging safely.
        if let adapter = caps.adapterKey {
            let value = (cmd.forceDischarge || !cmd.allowCharging) ? adapter.cutValue : 0x00
            success = client.writeByte(key: adapter.key, value: value)
        } else {
            success = false
        }

    default:
        success = false
    }

    if caps.hasACLC {
        switch cmd.magSafeLED {
        case "off": _ = client.writeByte(key: "ACLC", value: 1)
        case "green": _ = client.writeByte(key: "ACLC", value: 3)
        case "amber": _ = client.writeByte(key: "ACLC", value: 4)
        default: _ = client.writeByte(key: "ACLC", value: 0)
        }
    }

    applyLowPowerModeIfNeeded(cmd.lowPowerModeEnabled)
    return success
}

func runDaemon() {
    let client = SMCClient()
    let opened = client.open()
    defer { client.close() }
    let caps = SMCCapabilities(client: client)

    unlink(socketPath)
    let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else { exit(1) }
    defer { close(serverFD) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            _ = pathBytes.withUnsafeBufferPointer { src in
                memcpy(dest, src.baseAddress!, pathBytes.count)
            }
        }
    }

    let bindRes = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bindRes == 0, listen(serverFD, 16) == 0 else { exit(1) }
    chmod(socketPath, 0o666)

    while true {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else { continue }
        var noSigPipe: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var buffer = [UInt8](repeating: 0, count: 2048)
        let count = read(clientFD, &buffer, buffer.count)
        if count > 0 {
            let data = Data(buffer.prefix(count))
            if let cmd = try? JSONDecoder().decode(HelperCommand.self, from: data) {
                var effectiveMode = caps.backendMode
                let appliedOK = (cmd.pingOnly == true) ? opened : (opened && applySMC(cmd, client: client, caps: caps, resolvedMode: &effectiveMode))
                let ack = HelperAck(
                    ok: appliedOK,
                    backendMode: effectiveMode,
                    writableKeys: caps.writableKeyList
                )
                if var ackData = try? JSONEncoder().encode(ack) {
                    ackData.append(0x0A)
                    _ = ackData.withUnsafeBytes { buf in
                        write(clientFD, buf.baseAddress!, ackData.count)
                    }
                }
            }
        }
        close(clientFD)
    }
}

if CommandLine.arguments.contains("--daemon") {
    runDaemon()
} else {
    print("voltguard-helper ready. Pass --daemon to run socket service.")
}
