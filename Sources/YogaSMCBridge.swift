import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(IOKit)
import IOKit
#endif

/// Jembatan ke YogaSMC 1.5.3 (`ThinkVPC`), diadaptasi dari pola audit:
/// https://github.com/Syuhadak27/BatteryLenovoAssistent
///
/// Fakta penting (jangan dikarang):
/// - Threshold **bukan** SMC key `B0St`/`B0Sp`/`B0En` maupun `BCLM`.
/// - Set: properti IOUserClient `setCMstart` → ACPI `BCCS`, `setCMstop` → `BCSS`,
///   lewat `ThinkVPC::setPropertiesGated()`. `Battery`: 0=ANY, 1=PRIMARY, 2=SECONDARY.
/// - Kirim `Battery` dalam dictionary **terpisah lebih dulu** karena NSDictionary tidak berurutan.
/// - `stop = 100` dikirim sebagai `0` (YogaSMCPane). Disable: start=0, stop=0, inhibit=0.
/// - EC langsung: `YogaSMCUserClient` selector 0=open, 2=readEC(offset), 3=writeEC(offset,byte)
///   → method ACPI `RE1B`/`WE1B`. Offset harus 0x01–0x99 dan diverifikasi user.
enum YogaSMCBridgeError: LocalizedError {
    case thinkVPCNotFound
    case openFailed(IOReturn)
    case setFailed(IOReturn)
    case callFailed(String, IOReturn)

    var errorDescription: String? {
        switch self {
        case .thinkVPCNotFound:
            return "Layanan ThinkVPC (YogaSMC) tidak ditemukan. Pastikan YogaSMC 1.5.3 aktif dan SSDT pendukung terpasang (ioreg -lw0 | grep -i ThinkVPC)."
        case .openFailed(let kr):
            return String(format: "Gagal membuka koneksi YogaSMC (0x%08X).", kr)
        case .setFailed(let kr):
            return String(format: "Gagal menulis properti ThinkVPC (0x%08X). Mungkin membutuhkan hak akses lebih tinggi.", kr)
        case .callFailed(let name, let kr):
            return String(format: "YogaSMC %@ gagal (0x%08X). Cek ECAccessCap / method WE1B di namespace ACPI.", name, kr)
        }
    }
}

final class YogaSMCBridge {
    static let shared = YogaSMCBridge()
    private init() {}

    private enum ECSelector: UInt32 {
        case open = 0
        case close = 1
        case readEC = 2
        case writeEC = 3
    }

    private let lock = NSLock()
    private var ecConnection: io_connect_t = 0

    private var ioPort: mach_port_t { kIOMainPortDefault }

    deinit { closeECConnection() }

    // MARK: - Runtime detection

    static func isThinkVPCAvailable() -> Bool {
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("ThinkVPC"))
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
        #else
        return false
        #endif
    }

    private func copyThinkVPC() throws -> io_registry_entry_t {
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(ioPort, IOServiceMatching("ThinkVPC"))
        guard service != 0 else { throw YogaSMCBridgeError.thinkVPCNotFound }
        return service
        #else
        throw YogaSMCBridgeError.thinkVPCNotFound
        #endif
    }

    // MARK: - Threshold properties (ACPI BCCS / BCSS)

    /// Kirim dictionary secara berurutan. `Battery` harus lebih dulu supaya
    /// indeks baterai diset sebelum BCCS/BCSS dievaluasi.
    func setProperties(_ batches: [[String: Any]]) throws {
        #if canImport(IOKit)
        let service = try copyThinkVPC()
        defer { IOObjectRelease(service) }
        for props in batches {
            let cfProps = props as NSDictionary as CFTypeRef
            var kr = IORegistryEntrySetCFProperties(service, cfProps)
            if kr == kIOReturnSuccess { continue }

            // Fallback user client resmi YogaSMC.
            var connect: io_connect_t = 0
            let opened = IOServiceOpen(service, mach_task_self_, 0, &connect)
            guard opened == kIOReturnSuccess else { throw YogaSMCBridgeError.setFailed(kr) }
            defer { IOServiceClose(connect) }
            kr = IOConnectSetCFProperties(connect, cfProps)
            guard kr == kIOReturnSuccess else { throw YogaSMCBridgeError.setFailed(kr) }
        }
        #else
        throw YogaSMCBridgeError.thinkVPCNotFound
        #endif
    }

    /// Data mentah `BAT_PRIMARY` untuk diagnostik saja. Pemetaan BCTG vs BCSG
    /// tidak bisa dipastikan hanya dari binary, jadi tidak dipakai sebagai UI.
    func rawBatteryStatus() -> [String: Int]? {
        #if canImport(IOKit)
        guard let service = try? copyThinkVPC() else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(
            service, "BAT_PRIMARY" as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        guard let dict = raw.takeRetainedValue() as? NSDictionary else { return nil }
        var result: [String: Int] = [:]
        for key in ["BCTG", "BCSG", "BICG", "BDSG", "PSSG"] {
            if let number = dict[key] as? NSNumber {
                result[key] = number.intValue
            }
        }
        return result.isEmpty ? nil : result
        #else
        return nil
        #endif
    }

    // MARK: - Direct EC via YogaSMCUserClient (RE1B / WE1B)

    private func ensureECConnection() throws -> io_connect_t {
        lock.lock()
        defer { lock.unlock() }
        if ecConnection != 0 { return ecConnection }
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(ioPort, IOServiceMatching("ThinkVPC"))
        guard service != 0 else { throw YogaSMCBridgeError.thinkVPCNotFound }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connect)
        guard kr == kIOReturnSuccess else { throw YogaSMCBridgeError.openFailed(kr) }
        // writeEC/readEC menolak kalau provider belum di-open oleh client ini.
        let opened = IOConnectCallMethod(
            connect, ECSelector.open.rawValue,
            nil, 0, nil, 0, nil, nil, nil, nil
        )
        if opened != kIOReturnSuccess {
            NSLog("[SyStats:EC] userClientOpen returned 0x%08X", opened)
        }
        ecConnection = connect
        return connect
        #else
        throw YogaSMCBridgeError.thinkVPCNotFound
        #endif
    }

    func readECByte(_ offset: UInt8) throws -> UInt8 {
        let connect = try ensureECConnection()
        #if canImport(IOKit)
        var scalar = UInt64(offset)
        var output = UInt8(0)
        var outputSize = 1
        let kr = withUnsafePointer(to: &scalar) { scalarPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                withUnsafeMutablePointer(to: &outputSize) { sizePtr in
                    IOConnectCallMethod(
                        connect, ECSelector.readEC.rawValue,
                        scalarPtr, 1, nil, 0, nil, nil, outPtr, sizePtr
                    )
                }
            }
        }
        guard kr == kIOReturnSuccess else { throw YogaSMCBridgeError.callFailed("readEC", kr) }
        return output
        #else
        throw YogaSMCBridgeError.thinkVPCNotFound
        #endif
    }

    func writeECByte(_ offset: UInt8, _ value: UInt8) throws {
        let connect = try ensureECConnection()
        #if canImport(IOKit)
        var scalar = UInt64(offset)
        var input = value
        let kr = withUnsafePointer(to: &scalar) { scalarPtr in
            withUnsafePointer(to: &input) { inPtr in
                IOConnectCallMethod(
                    connect, ECSelector.writeEC.rawValue,
                    scalarPtr, 1, inPtr, 1, nil, nil, nil, nil
                )
            }
        }
        guard kr == kIOReturnSuccess else { throw YogaSMCBridgeError.callFailed("writeEC", kr) }
        #else
        throw YogaSMCBridgeError.thinkVPCNotFound
        #endif
    }

    func closeECConnection() {
        lock.lock()
        defer { lock.unlock() }
        guard ecConnection != 0 else { return }
        #if canImport(IOKit)
        _ = IOConnectCallMethod(
            ecConnection, ECSelector.close.rawValue,
            nil, 0, nil, 0, nil, nil, nil, nil
        )
        IOServiceClose(ecConnection)
        #endif
        ecConnection = 0
    }
}
