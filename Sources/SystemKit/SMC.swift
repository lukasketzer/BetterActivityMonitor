import Foundation
import IOKit

/// Minimal AppleSMC client. One key read costs ~0.6 ms, versus ~8 ms per sensor through IOHIDEventSystem.
final class SMC {
    // Mirrors the kernel's SMCKeyData_t (80 bytes). Swift lays structs out in declaration order;
    // `pad` reproduces C's tail padding of the key-info struct so later offsets match.
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PowerLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0 }
    struct KeyInfo { var size: UInt32 = 0, type: UInt32 = 0, attributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var limit = PowerLimit()
        var info = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var index: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private enum Command: UInt8 { case readBytes = 5, keyAtIndex = 8, keyInfo = 9 }

    private var connection: io_connect_t = 0

    init?() {
        guard MemoryLayout<Param>.size == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(connection) }

    static func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    static func name(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, encoding: .ascii) ?? "????"
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let r = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &size)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    func info(_ key: UInt32) -> KeyInfo? {
        var p = Param()
        p.key = key
        p.command = Command.keyInfo.rawValue
        return call(&p)?.info
    }

    func key(at index: UInt32) -> UInt32? {
        var p = Param()
        p.command = Command.keyAtIndex.rawValue
        p.index = index
        return call(&p)?.key
    }

    private func bytes(_ key: UInt32, _ info: KeyInfo) -> (UInt64, UInt64, UInt64, UInt64)? {
        var p = Param()
        p.key = key
        p.info.size = info.size
        p.command = Command.readBytes.rawValue
        return call(&p)?.bytes
    }

    /// Reads `flt `, `sp78` (Intel temperatures) and unsigned integer keys as Double.
    func value(_ key: UInt32, _ info: KeyInfo) -> Double? {
        guard var raw = bytes(key, info) else { return nil }
        return withUnsafeBytes(of: &raw) { b -> Double? in
            switch SMC.name(info.type) {
            case "flt ": return Double(b.load(as: Float.self))
            case "sp78": return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
            case "ui8 ": return Double(b[0])
            case "ui16": return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
            case "ui32": return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
            case "fpe2": return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
            default: return nil
            }
        }
    }

    var keyCount: UInt32 {
        let key = SMC.code("#KEY")
        guard let info = info(key), let v = value(key, info) else { return 0 }
        return UInt32(v)
    }
}
