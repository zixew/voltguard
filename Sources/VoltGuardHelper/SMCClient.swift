import Foundation
import IOKit

struct SMCKeyData {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

final class SMCClient {
    private var connection: io_connect_t = 0

    func open() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    deinit {
        close()
    }

    @discardableResult
    func writeByte(key: String, value: UInt8) -> Bool {
        writeBytes(key: key, values: [value])
    }

    @discardableResult
    func writeBytes(key: String, values: [UInt8]) -> Bool {
        guard connection != 0, key.utf8.count == 4, !values.isEmpty, values.count <= 32 else { return false }
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = fourCharCode(key)
        input.data8 = 9 // kSMCGetKeyInfo
        let infoRes = callSMC(input: &input, output: &output)
        guard infoRes == kIOReturnSuccess, output.result == 0, output.keyInfo.dataSize >= 1 else {
            return false
        }

        var writeInput = SMCKeyData()
        var writeOutput = SMCKeyData()
        writeInput.key = fourCharCode(key)
        writeInput.keyInfo.dataSize = output.keyInfo.dataSize
        writeInput.data8 = 6 // kSMCWriteKey
        withUnsafeMutableBytes(of: &writeInput.bytes) { rawBuf in
            for (index, byte) in values.prefix(Int(output.keyInfo.dataSize)).enumerated() {
                rawBuf[index] = byte
            }
        }
        let writeRes = callSMC(input: &writeInput, output: &writeOutput)
        return writeRes == kIOReturnSuccess && writeOutput.result == 0
    }

    private func callSMC(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            2, // kSMCHandleYPCEvent
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
    }

    private func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in str.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }
}
