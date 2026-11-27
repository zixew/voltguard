import Foundation

struct HelperCommand: Decodable {
    let limitPercent: Int
    let allowCharging: Bool
    let forceDischarge: Bool
    let magSafeLED: String
    let lowPowerModeEnabled: Bool?
}

let socketPath = "/var/run/voltguard-helper.sock"
var lastAppliedLowPower: Bool?

func applyLowPowerModeIfNeeded(_ enabled: Bool?) {
    guard let enabled, enabled != lastAppliedLowPower else { return }
    lastAppliedLowPower = enabled
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-a", "lowpowermode", enabled ? "1" : "0"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
}

func applySMC(_ cmd: HelperCommand, client: SMCClient) {
    // Apple Silicon (M1/M2/M3/M4) & Intel SMC keys:
    // BCLM/CHWA for charge limit, CH0B/CH0C/CH0I/CHTE & CHIE/CH0J for inhibit/discharge, ACLC for MagSafe LED.
    let clamped = UInt8(min(max(cmd.limitPercent, 20), 100))
    _ = client.writeByte(key: "BCLM", value: clamped)

    if cmd.forceDischarge {
        _ = client.writeByte(key: "CH0I", value: 1)
        _ = client.writeByte(key: "CH0J", value: 1)
        _ = client.writeByte(key: "CH0B", value: 2)
        _ = client.writeByte(key: "CH0C", value: 2)
        _ = client.writeByte(key: "CHIE", value: 0x08)
        _ = client.writeBytes(key: "CHTE", values: [0x01, 0x00, 0x00, 0x00])
    } else if !cmd.allowCharging {
        _ = client.writeByte(key: "CH0I", value: 0)
        _ = client.writeByte(key: "CH0J", value: 0)
        _ = client.writeByte(key: "CH0B", value: 2)
        _ = client.writeByte(key: "CH0C", value: 2)
        _ = client.writeByte(key: "CHIE", value: 0x00)
        _ = client.writeByte(key: "CHCC", value: 0)
        _ = client.writeBytes(key: "CHTE", values: [0x01, 0x00, 0x00, 0x00])
    } else {
        _ = client.writeByte(key: "CH0I", value: 0)
        _ = client.writeByte(key: "CH0J", value: 0)
        _ = client.writeByte(key: "CH0B", value: 0)
        _ = client.writeByte(key: "CH0C", value: 0)
        _ = client.writeByte(key: "CHIE", value: 0x00)
        _ = client.writeByte(key: "CHCC", value: 1)
        _ = client.writeBytes(key: "CHTE", values: [0x00, 0x00, 0x00, 0x00])
    }

    switch cmd.magSafeLED {
    case "off": _ = client.writeByte(key: "ACLC", value: 1)
    case "green": _ = client.writeByte(key: "ACLC", value: 3)
    case "amber": _ = client.writeByte(key: "ACLC", value: 4)
    default: _ = client.writeByte(key: "ACLC", value: 0)
    }

    applyLowPowerModeIfNeeded(cmd.lowPowerModeEnabled)
}

func runDaemon() {
    let client = SMCClient()
    _ = client.open()
    defer { client.close() }

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
    guard bindRes == 0, listen(serverFD, 8) == 0 else { exit(1) }
    chmod(socketPath, 0o666)

    while true {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else { continue }
        var buffer = [UInt8](repeating: 0, count: 2048)
        let count = read(clientFD, &buffer, buffer.count)
        close(clientFD)
        if count > 0 {
            let data = Data(buffer.prefix(count))
            if let cmd = try? JSONDecoder().decode(HelperCommand.self, from: data) {
                applySMC(cmd, client: client)
            }
        }
    }
}

if CommandLine.arguments.contains("--daemon") {
    runDaemon()
} else {
    print("voltguard-helper ready. Pass --daemon to run socket service.")
}
