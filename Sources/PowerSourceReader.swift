import Foundation
#if canImport(IOKit)
import IOKit
import IOKit.ps
#endif

struct PowerSourceSample {
    var source: PowerSource = .unknown
    var battery = BatteryStatus()
    var electrical = ElectricalReading()
    var diagnostics: [String] = []
}

/// Reads public IOPowerSources data and, when available, augments charger
/// voltage/current from SMC keys. All keys are treated as optional: on a
/// Hackintosh they may not exist at all.
enum PowerSourceReader {
    static func read() -> PowerSourceSample {
        var sample = PowerSourceSample()
        #if canImport(IOKit)
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            sample.diagnostics.append("IOPSCopyPowerSourcesInfo returned no data.")
            return sample
        }
        guard let cfList = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() else {
            sample.diagnostics.append("IOPSCopyPowerSourcesList returned no data.")
            return sample
        }
        let list = cfList as? [CFTypeRef] ?? []
        var foundAC = false
        var foundBattery = false

        for powerSource in list {
            // "Get rule": IOPSGetPowerSourceDescription TIDAK mengembalikan objek
            // yang di-retain. takeRetainedValue() di sini = over-release → crash
            // (EXC_BAD_ACCESS) beberapa detik setelah app jalan di laptop.
            guard let dict = IOPSGetPowerSourceDescription(blob, powerSource)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let state = string(dict, "Power Source State") ?? ""
            let type = string(dict, "Type") ?? ""

            if state == "AC Power" { foundAC = true }

            // Saat charger terpasang, Type = "InternalBattery" dan state = "AC Power";
            // cek lama (state == "Battery Power") membuat data baterai kosong saat charging.
            let isBattery = type == "InternalBattery" || type == "Battery" || state == "Battery Power"
            if isBattery {
                foundBattery = true
                sample.battery.isPresent = true
                sample.battery.chargePercent = percent(dict, "Current Capacity", "Max Capacity")
                sample.battery.isCharging = bool(dict, "Is Charging")
                // -1 = macOS masih menghitung; jangan tampilkan sebagai menit.
                let toEmpty = int(dict, "Time to Empty").flatMap { $0 >= 0 ? $0 : nil }
                let toFull = int(dict, "Time to Full Charge").flatMap { $0 >= 0 ? $0 : nil }
                sample.battery.timeRemainingMinutes = (sample.battery.isCharging == true) ? toFull : toEmpty
                sample.battery.cycleCount = int(dict, "Cycle Count")
                sample.battery.health = string(dict, "Battery Health")
                    ?? string(dict, "Battery Health Condition")
                sample.battery.source = "IOPowerSources"

                // IOPS memakai KONSTANTA kIOPSVoltageKey / kIOPSCurrentKey,
                // bukan string literal "Voltage"/"Current". Menggunakan literal
                // membuat kedua nilai selalu nil di banyak Hackintosh.
                if let v = validInt(dict[kIOPSVoltageKey as String], in: 1...50_000) {
                    let volts = Double(v) / 1000.0
                    sample.electrical.voltage = volts
                    sample.electrical.voltageSource = "IOPowerSources \(kIOPSVoltageKey as String)"
                }
                if let a = validInt(dict[kIOPSCurrentKey as String], in: -100_000...100_000), a != 0 {
                    sample.electrical.current = Double(a) / 1000.0
                    sample.electrical.currentSource = "IOPowerSources \(kIOPSCurrentKey as String)"
                }
            }
        }

        // Fallback AppleSmartBattery di IORegistry. Sering menjadi satu-satunya
        // sumber V/A yang benar-benar hidup di Hackintosh + VirtualSMC/YogaSMC.
        // Logika ini diport dari referensi BatteryLenovoAssistent (terbukti jalan).
        let registry = Self.appleSmartBatteryElectrical()
        if sample.electrical.voltage == nil, let mv = registry.voltage {
            sample.electrical.voltage = Double(mv) / 1000.0
            sample.electrical.voltageSource = "AppleSmartBattery Voltage"
        }
        if sample.electrical.current == nil, let ma = registry.current {
            sample.electrical.current = Double(ma) / 1000.0
            sample.electrical.currentSource = "AppleSmartBattery \(registry.currentKey)"
        }

        if foundAC { sample.source = .ac }
        else if foundBattery { sample.source = .battery }
        else { sample.source = .unknown }

        // Kandidat SMC tambahan (VirtualSMC / SMCBatteryManager / YogaSMC).
        // Key yang TIDAK ada di SMC hanya menghasilkan nil, tanpa efek samping.
        if sample.source == .ac {
            if sample.electrical.voltage == nil,
               let hit = SMCReader.shared.firstPlausibleNumber(for: ["VDCR", "VDDR", "B0AV", "DG0R", "BG0R"], in: 1...60) {
                let volts = hit.value > 100 ? hit.value / 1000.0 : hit.value
                if volts < 60 {
                    sample.electrical.voltage = volts
                    sample.electrical.voltageSource = "SMC \(hit.key)"
                }
            }
            if sample.electrical.current == nil,
               let hit = SMCReader.shared.firstPlausibleNumber(for: ["IDCR", "IB0R", "IB1R", "ID0R", "B0AC"], in: 0.001...20) {
                let amps = hit.value > 20 ? hit.value / 1000.0 : hit.value
                if amps < 20 {
                    sample.electrical.current = amps
                    sample.electrical.currentSource = "SMC \(hit.key)"
                }
            }
        } else if sample.source == .battery, sample.electrical.voltage == nil {
            if let hit = SMCReader.shared.firstPlausibleNumber(for: ["VDDR", "B0AV"], in: 1...60) {
                let volts = hit.value > 100 ? hit.value / 1000.0 : hit.value
                if volts < 60 {
                    sample.electrical.voltage = volts
                    sample.electrical.voltageSource = "SMC \(hit.key)"
                }
            }
        }

        // Wattage: V(mV) × A(mA) / 1e6 sesuai referensi BatteryLenovoAssistent.
        // Fallback: SMC PDTR (adapter power) / PPBR (battery power), lalu watt
        // dari IOPSCopyExternalPowerAdapterDetails(). Tidak ada angka rekaan.
        if sample.electrical.power == nil,
           let v = sample.electrical.voltage, let a = sample.electrical.current {
            sample.electrical.power = abs(v * a)
            sample.electrical.powerSourceName = "computed V × A"
        }
        if sample.electrical.power == nil {
            if sample.source == .ac,
               let hit = SMCReader.shared.firstPlausibleNumber(for: ["PDTR", "WDCR"], in: 1...500) {
                sample.electrical.power = hit.value
                sample.electrical.powerSourceName = "SMC \(hit.key)"
            } else if let hit = SMCReader.shared.firstPlausibleNumber(for: ["PPBR"], in: 1...500) {
                sample.electrical.power = hit.value
                sample.electrical.powerSourceName = "SMC \(hit.key)"
            }
        }
        if sample.electrical.power == nil, sample.source == .ac,
           let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = validInt(details[kIOPSPowerAdapterWattsKey as String], in: 1...500) {
            sample.electrical.power = Double(watts)
            sample.electrical.powerSourceName = "IOPS adapter watts"
        }

        if sample.electrical.voltage == nil {
            sample.diagnostics.append("Voltage: IOPowerSources / AppleSmartBattery / SMC Kandidat tidak terbaca.")
        }
        if sample.electrical.current == nil {
            sample.diagnostics.append("Current: IOPowerSources / AppleSmartBattery / SMC Kandidat tidak terbaca.")
        }
        if sample.electrical.power == nil {
            sample.diagnostics.append("Wattage: tidak bisa dihitung (V atau A kosong) dan SMC PDTR/PPBR + adapter watts tidak terbaca.")
        }
        #else
        sample.diagnostics.append("IOKit is unavailable in this build.")
        #endif
        return sample
    }

    // MARK: - Dictionary helpers

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        if let value = dict[key] as? String { return value }
        if let value = dict[key] as? NSNumber { return value.stringValue }
        return nil
    }

    private static func number(_ dict: [String: Any], _ key: String) -> Double? {
        if let value = dict[key] as? NSNumber { return value.doubleValue }
        if let value = dict[key] as? Double { return value }
        if let value = dict[key] as? Int { return Double(value) }
        return nil
    }

    private static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let value = dict[key] as? NSNumber { return value.intValue }
        if let value = dict[key] as? Int { return value }
        return nil
    }

    private static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        if let value = dict[key] as? NSNumber { return value.boolValue }
        if let value = dict[key] as? Bool { return value }
        return nil
    }

    private static func validInt(_ value: Any?, in range: ClosedRange<Int>) -> Int? {
        guard let number = (value as? NSNumber)?.intValue, range.contains(number) else { return nil }
        return number
    }

    /// Nilai V/A mentah (mV / mA) dari AppleSmartBattery di IORegistry.
    /// Diport dari BatteryLenovoAssistent/LivePowerReader (terbukti di Hackintosh).
    private static func appleSmartBatteryElectrical() -> (voltage: Int?, current: Int?, currentKey: String) {
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return (nil, nil, "unavailable") }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil, "unavailable")
        }
        let voltage = validInt(dict["Voltage"], in: 1...50_000)
        if let ma = validInt(dict["InstantAmperage"], in: -100_000...100_000) {
            return (voltage, ma, "InstantAmperage")
        }
        if let ma = validInt(dict["Amperage"], in: -100_000...100_000) {
            return (voltage, ma, "Amperage")
        }
        return (voltage, nil, "unavailable")
        #else
        return (nil, nil, "unavailable")
        #endif
    }

    private static func percent(_ dict: [String: Any], _ currentKey: String, _ maxKey: String) -> Double? {
        guard let current = number(dict, currentKey), let max = number(dict, maxKey), max > 0 else { return nil }
        return Swift.min(Swift.max(100.0 * current / max, 0), 100)
    }
}
