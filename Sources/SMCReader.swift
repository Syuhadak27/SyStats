import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(IOKit)
import IOKit
#endif

/// Hasil baca satu SMC key lengkap dengan tipe datanya.
struct SMCValue {
    let key: String
    let type: String      // mis. "sp78", "fpe2", "flt ", "ui8 "
    let bytes: [UInt8]    // sepanjang dataSize

    /// Decode sesuai tipe SMC yang SEBENARNYA dilaporkan key tersebut
    /// (bukan menebak semua encoding sekaligus).
    var number: Double? {
        guard !bytes.isEmpty else { return nil }
        let value: Double?
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            // Float32 native-endian (little endian di x86_64 & arm64).
            let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            value = Double(Float(bitPattern: raw))
        case "ui8 ", "flag":
            value = Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let raw = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            value = Double(raw)
        case "si8 ":
            value = Double(Int8(bitPattern: bytes[0]))
        case "si16":
            guard bytes.count >= 2 else { return nil }
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1])))
        default:
            value = SMCValue.fixedPoint(type: type, bytes: bytes)
        }
        guard let result = value, result.isFinite else { return nil }
        return result
    }

    /// Fixed point: "spXY" (signed) / "fpXY" (unsigned); karakter ke-4 = jumlah
    /// bit pecahan dalam hex (sp78 → 8 bit, fpe2 → 2 bit). Lebar 16 bit.
    private static func fixedPoint(type: String, bytes: [UInt8]) -> Double? {
        let chars = Array(type)
        guard chars.count == 4, bytes.count >= 2 else { return nil }
        let prefix = String(chars[0...1])
        guard prefix == "sp" || prefix == "fp",
              let fractionBits = Int(String(chars[3]), radix: 16) else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let divisor = Double(1 << fractionBits)
        if prefix == "sp" {
            return Double(Int16(bitPattern: raw)) / divisor
        }
        return Double(raw) / divisor
    }
}

/// Minimal AppleSMC user-client reader (read-only).
///
/// Layout `SMCKeyData_t` (80 byte, sama dengan VirtualSMC & AppleSMC asli):
///   0  key (UInt32, big-endian secara numerik → di memori little-endian)
///  28  keyInfo.dataSize  (UInt32)
///  32  keyInfo.dataType  (UInt32, empat karakter)
///  40  result (UInt8)    — 0 = sukses
///  42  data8  (UInt8)    — perintah: 9 = getKeyInfo, 5 = readKey
///  48  bytes[32]         — data hasil baca
/// Selector user-client = 2 (kSMCHandleYPCEvent).
///
/// Versi lama memakai offset yang salah (key urut byte, keySize di offset 5,
/// command di offset 48, data di offset 13) sehingga SEMUA pembacaan gagal
/// diam-diam dan fan/suhu selalu "—".
final class SMCReader {
    static let shared = SMCReader()

    private let openLock = NSLock()
    private let callLock = NSLock()
    private var connection: io_connect_t = 0
    private var isOpen = false
    private var didAttemptOpen = false

    private static let structSize = 80
    private static let selectorHandleYPCEvent: UInt32 = 2
    private static let cmdReadKey: UInt8 = 5
    private static let cmdGetKeyInfo: UInt8 = 9

    deinit {
        #if canImport(IOKit)
        if isOpen { IOServiceClose(connection) }
        #endif
    }

    private func ensureOpen() -> Bool {
        openLock.lock()
        defer { openLock.unlock() }
        if isOpen { return true }
        if didAttemptOpen { return false }
        didAttemptOpen = true
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var newConnection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &newConnection)
        guard result == KERN_SUCCESS, newConnection != 0 else { return false }
        connection = newConnection
        isOpen = true
        return true
        #else
        return false
        #endif
    }

    #if canImport(IOKit)
    private static func fourCC(_ text: String) -> UInt32? {
        let utf8 = Array(text.utf8)
        guard utf8.count == 4 else { return nil }
        return (UInt32(utf8[0]) << 24) | (UInt32(utf8[1]) << 16)
            | (UInt32(utf8[2]) << 8) | UInt32(utf8[3])
    }

    /// UInt32 little-endian (urutan memori native x86_64 / arm64) dari buffer.
    private static func nativeUInt32(_ buffer: [UInt8], at offset: Int) -> UInt32 {
        UInt32(buffer[offset]) | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16) | (UInt32(buffer[offset + 3]) << 24)
    }

    private static func string(fromFourCC value: UInt32) -> String {
        let scalars = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                       UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        return String(decoding: scalars, as: UTF8.self)
    }

    /// Satu panggilan struct ke AppleSMC. `fill` menyiapkan input, hasil dikembalikan
    /// sebagai buffer 80 byte atau nil bila IOKit / SMC menolak.
    private func call(_ fill: (UnsafeMutableRawPointer) -> Void) -> [UInt8]? {
        let size = SMCReader.structSize
        let input = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        let output = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer {
            input.deallocate()
            output.deallocate()
        }
        input.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        output.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        fill(input)

        var outputSize = size
        let status = IOConnectCallStructMethod(
            connection, SMCReader.selectorHandleYPCEvent,
            input, size, output, &outputSize
        )
        guard status == KERN_SUCCESS else { return nil }
        let buffer = (0..<size).map { output.load(fromByteOffset: $0, as: UInt8.self) }
        guard buffer[40] == 0 else { return nil } // result != 0 → key tidak ada / ditolak
        return buffer
    }
    #endif

    /// Baca key beserta tipenya. `nil` bila key tidak ada atau tidak terbaca.
    func value(for key: String) -> SMCValue? {
        #if canImport(IOKit)
        guard let keyCode = SMCReader.fourCC(key) else { return nil }
        guard ensureOpen() else { return nil }
        callLock.lock()
        defer { callLock.unlock() }

        // 1) getKeyInfo → ukuran & tipe data
        guard let info = call({ input in
            input.storeBytes(of: keyCode, toByteOffset: 0, as: UInt32.self)
            input.storeBytes(of: SMCReader.cmdGetKeyInfo, toByteOffset: 42, as: UInt8.self)
        }) else { return nil }

        let dataSize = SMCReader.nativeUInt32(info, at: 28)
        let dataType = SMCReader.nativeUInt32(info, at: 32)
        guard dataSize > 0, dataSize <= 32 else { return nil }

        // 2) readKey
        guard let read = call({ input in
            input.storeBytes(of: keyCode, toByteOffset: 0, as: UInt32.self)
            input.storeBytes(of: dataSize, toByteOffset: 28, as: UInt32.self)
            input.storeBytes(of: SMCReader.cmdReadKey, toByteOffset: 42, as: UInt8.self)
        }) else { return nil }

        let bytes = Array(read[48..<(48 + Int(dataSize))])
        return SMCValue(key: key, type: SMCReader.string(fromFourCC: dataType), bytes: bytes)
        #else
        return nil
        #endif
    }

    /// Nilai numerik hasil decode sesuai tipe key, atau nil.
    func number(for key: String) -> Double? {
        value(for: key)?.number
    }

    /// Nilai numerik yang masuk akal (default: > 0 dan < 100.000).
    func plausibleNumber(for key: String, in range: ClosedRange<Double> = 0.0001...100_000) -> Double? {
        guard let number = number(for: key), range.contains(number) else { return nil }
        return number
    }

    func firstPlausibleNumber(
        for keys: [String], in range: ClosedRange<Double> = 0.0001...100_000
    ) -> (value: Double, key: String)? {
        for key in keys {
            if let value = plausibleNumber(for: key, in: range) {
                return (value, key)
            }
        }
        return nil
    }
}
