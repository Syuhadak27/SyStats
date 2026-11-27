import Foundation

/// Fan and CPU temperature via SMC keys.
///
/// ASSUMPTIONS: `FNum` / `F0Ac`…`F4Ac` (fan count / actual RPM) and
/// `TC0D`, `TC0P`, `TN0P` (CPU die / proximity temperature). These keys exist
/// on many Intel Macs and some VirtualSMC/SMCSuperIO setups, but they are not
/// guaranteed. A missing key yields `nil` and an explicit GUI diagnostic.
enum SensorReader {
    static func readFan() -> FanReading {
        var reading = FanReading()
        let count = SMCReader.shared.plausibleNumber(for: "FNum")
        let fanCount = count.map { Int($0) }.flatMap { $0 > 0 && $0 <= 8 ? $0 : nil }
        reading.fanCount = fanCount

        let keys = fanCount.map { limit in
            (0..<limit).map { "F\($0)Ac" }
        } ?? ["F0Ac", "F1Ac"]
        if let hit = SMCReader.shared.firstPlausibleNumber(for: keys) {
            reading.rpm = hit.value
            reading.source = "SMC \(hit.key)"
        }
        return reading
    }

    static func readTemperature() -> ThermalReading {
        var reading = ThermalReading()
        if let hit = SMCReader.shared.firstPlausibleNumber(for: ["TC0D", "TC0P", "TN0P", "TC0c"]) {
            reading.cpuTemperatureC = hit.value
            reading.source = "SMC \(hit.key)"
        }
        return reading
    }
}
