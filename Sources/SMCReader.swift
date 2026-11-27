import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(IOKit)
import IOKit
#endif

/// Minimal AppleSMC user-client reader.
///
/// ASSUMPTIONS (documented on purpose): this uses the widely used AppleSMC
/// user-client layout — selector 2, 80-byte parameter block, key at offset 0,
/// keySize at offset 5, read command at offset 48, returned data at offset 13.
/// Many real Macs and VirtualSMC/Hackintosh SMC implementations expose only a
/// subset of keys. Any failure returns `nil` so the UI can say "unavailable"
/// instead of inventing numbers.
final class SMCReader {
    static let shared = SMCReader()

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var isOpen = false
    private var didAttemptOpen = false

    deinit {
        if isOpen {
            #if canImport(IOKit)
            IOServiceClose(connection)
            #endif
        }
    }

    private func ensureOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
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
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { return false }
        isOpen = true
        return true
        #else
        return false
        #endif
    }

    /// Raw key data (up to 32 bytes) or `nil` when the key is not readable.
    func data(for key: String) -> [UInt8]? {
        guard ensureOpen() else { return nil }
        #if canImport(IOKit)
        let input = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
        let output = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
        defer {
            input.deallocate()
            output.deallocate()
        }
        input.initializeMemory(as: UInt8.self, repeating: 0, count: 80)
        output.initializeMemory(as: UInt8.self, repeating: 0, count: 80)

        let keyBytes = Array(key.utf8.prefix(4))
        for (index, byte) in keyBytes.enumerated() {
            input.storeBytes(of: byte, toByteOffset: index, as: UInt8.self)
        }
        input.storeBytes(of: UInt8(32), toByteOffset: 5, as: UInt8.self) // keySize
        input.storeBytes(of: UInt8(5), toByteOffset: 48, as: UInt8.self) // read command

        var outputCount = 80
        let status = IOConnectCallStructMethod(connection, 2, input, 80, output, &outputCount)
        guard status == KERN_SUCCESS else { return nil }
        return (0..<32).map { output.load(fromByteOffset: 13 + $0, as: UInt8.self) }
        #else
        return nil
        #endif
    }

    // MARK: - Common SMC encodings

    /// Catatan: SMCReader sengaja **read-only**. Audit kext YogaSMC 1.5.3
    /// menunjukkan threshold tidak memakai SMC key (BCLM/B0St/B0Sp/B0En bukan
    /// jalur threshold). Penulisan dilakukan oleh `YogaSMCBridge` lewat
    /// properti ThinkVPC / method ACPI BCCS-BCSS-WE1B.

    /// sp78: signed 7.8 fixed point, big endian (temperatures, voltages).
    func sp78(_ key: String) -> Double? {
        guard let bytes = data(for: key), bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        let value = Double(raw) / 256.0
        return value.isFinite ? value : nil
    }

    /// ui32: unsigned 32-bit little endian (some fan / current keys).
    func ui32(_ key: String) -> Double? {
        guard let bytes = data(for: key), bytes.count >= 4 else { return nil }
        let value = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        return Double(value)
    }

    /// fpe2: unsigned 14.2 fixed point, big endian (classic fan RPM keys).
    func fpe2(_ key: String) -> Double? {
        guard let bytes = data(for: key), bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / 4.0
    }

    /// Try the encodings used by the usual fan/temperature/charger keys and
    /// return the first plausible positive reading.
    func plausibleNumber(for key: String) -> Double? {
        let candidates = [sp78(key), fpe2(key), ui32(key)].compactMap { $0 }
        return candidates.first { $0 > 0 && $0 < 100_000 }
    }

    func firstPlausibleNumber(for keys: [String]) -> (value: Double, key: String)? {
        for key in keys {
            if let value = plausibleNumber(for: key) {
                return (value, key)
            }
        }
        return nil
    }
}
