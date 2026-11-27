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

                // Some IOKit implementations expose raw battery V/I here.
                if let v = number(dict, "Voltage"), v > 0 {
                    let volts = v > 100 ? v / 1000.0 : v
                    sample.electrical.voltage = volts
                    sample.electrical.voltageSource = "IOPowerSources"
                }
                if let a = number(dict, "Current") {
                    let amps = abs(a) > 20 ? a / 1000.0 : a
                    sample.electrical.current = amps
                    sample.electrical.currentSource = "IOPowerSources"
                }
            }
        }

        if foundAC { sample.source = .ac }
        else if foundBattery { sample.source = .battery }
        else { sample.source = .unknown }

        // Charger electrical values: IOPowerSources rarely exposes them, so
        // fall back to commonly used Intel SMC keys (VirtualSMC may not have them).
        if sample.source == .ac {
            if sample.electrical.voltage == nil,
               let hit = SMCReader.shared.firstPlausibleNumber(for: ["VDCR", "VDDR"]) {
                let volts = hit.value > 100 ? hit.value / 1000.0 : hit.value
                if volts < 60 {
                    sample.electrical.voltage = volts
                    sample.electrical.voltageSource = "SMC \(hit.key)"
                }
            }
            if sample.electrical.current == nil,
               let hit = SMCReader.shared.firstPlausibleNumber(for: ["IDCR", "IB0R"]) {
                let amps = hit.value > 20 ? hit.value / 1000.0 : hit.value
                if amps < 20 {
                    sample.electrical.current = amps
                    sample.electrical.currentSource = "SMC \(hit.key)"
                }
            }
        } else if sample.source == .battery, sample.electrical.voltage == nil {
            if let hit = SMCReader.shared.firstPlausibleNumber(for: ["VDDR"]) {
                let volts = hit.value > 100 ? hit.value / 1000.0 : hit.value
                if volts < 60 {
                    sample.electrical.voltage = volts
                    sample.electrical.voltageSource = "SMC \(hit.key)"
                }
            }
        }

        if let v = sample.electrical.voltage, let a = sample.electrical.current {
            sample.electrical.power = v * abs(a)
            sample.electrical.powerSourceName = "computed V × A"
        } else if let w = SMCReader.shared.firstPlausibleNumber(for: ["WDCR"]), w.value < 500 {
            sample.electrical.power = w.value
            sample.electrical.powerSourceName = "SMC \(w.key)"
        }

        if sample.electrical.voltage == nil {
            sample.diagnostics.append("Voltage: not exposed by IOPowerSources; SMC VDCR/VDDR unavailable or unsupported by this SMC.")
        }
        if sample.electrical.current == nil {
            sample.diagnostics.append("Current: not exposed by IOPowerSources; SMC IDCR/IB0R unavailable or unsupported by this SMC.")
        }
        if sample.electrical.power == nil {
            sample.diagnostics.append("Wattage: cannot be computed without both V and A, and no SMC wattage key was readable.")
        }
        #else
        sample.diagnostics.append("IOKit is unavailable in this build.")
        #endif
        return sample
    }

    // MARK: - Dictionary helpers

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        if let value = dict[key] as? String { return value }
        if let value = dict[key] as? CFString { return value as String }
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

    private static func percent(_ dict: [String: Any], _ currentKey: String, _ maxKey: String) -> Double? {
        guard let current = number(dict, currentKey), let max = number(dict, maxKey), max > 0 else { return nil }
        return Swift.min(Swift.max(100.0 * current / max, 0), 100)
    }
}
