import Foundation

// MARK: - Power state

enum PowerSource: String {
    case ac = "AC"
    case battery = "Battery"
    case unknown = "Unknown"

    var label: String {
        switch self {
        case .ac: return "Charger connected"
        case .battery: return "On battery"
        case .unknown: return "Power source unknown"
        }
    }
}

/// How the compact menu bar string is rendered.
enum MenuBarMode: String, CaseIterable, Identifiable {
    case automatic
    case ac
    case battery

    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return "Automatic (follows charger)"
        case .ac: return "Always AC (V / A / W)"
        case .battery: return "Always Battery (CPU / RAM / RPM / °C)"
        }
    }
}

// MARK: - Individual readings

/// Electrical telemetry. Every value is optional: on many Hackintoshes the
/// public IOPowerSources dictionary does NOT expose charger V/A and VirtualSMC
/// does not implement every Apple SMC key. Missing data is reported, never faked.
struct ElectricalReading {
    var voltage: Double?
    var current: Double?
    var power: Double?
    var voltageSource: String = "unavailable"
    var currentSource: String = "unavailable"
    var powerSourceName: String = "unavailable"
    var isEstimated: Bool = false

    var hasAnyValue: Bool { voltage != nil || current != nil || power != nil }
}

struct BatteryStatus {
    var isPresent: Bool = false
    var chargePercent: Double?
    var isCharging: Bool?
    var timeRemainingMinutes: Int?
    var cycleCount: Int?
    var health: String?
    var source: String = "IOPowerSources"
}

struct ThermalReading {
    var cpuTemperatureC: Double?
    var source: String = "unavailable"

    var hasValue: Bool { cpuTemperatureC != nil }
}

struct FanReading {
    var rpm: Double?
    var fanCount: Int?
    var source: String = "unavailable"

    var hasValue: Bool { rpm != nil }
}

/// A single immutable sample used by both the GUI and the menu bar controller.
struct TelemetrySnapshot {
    var timestamp: Date = Date()
    var powerSource: PowerSource = .unknown
    var battery = BatteryStatus()
    var electrical = ElectricalReading()
    var cpuUsagePercent: Double?
    var ramUsagePercent: Double?
    var fan = FanReading()
    var thermal = ThermalReading()
    var diagnostics: [String] = []

    // MARK: Formatting (kept deliberately compact for the menu bar)

    private func value(_ number: Double?, decimals: Int, suffix: String) -> String {
        guard let number, number.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", number) + suffix
    }

    var voltageText: String { value(electrical.voltage, decimals: 1, suffix: "V") }
    var currentText: String { value(electrical.current, decimals: 2, suffix: "A") }
    var powerText: String { value(electrical.power, decimals: 1, suffix: "W") }
    var cpuText: String { value(cpuUsagePercent, decimals: 0, suffix: "%") }
    var ramText: String { value(ramUsagePercent, decimals: 0, suffix: "%") }
    var fanText: String { value(fan.rpm, decimals: 0, suffix: " RPM") }
    var temperatureText: String { value(thermal.cpuTemperatureC, decimals: 0, suffix: "°C") }
    var batteryText: String { value(battery.chargePercent, decimals: 0, suffix: "%") }

    /// Resolved mode for the menu bar (Automatic follows the charger state).
    func resolvedMode(preferred: MenuBarMode) -> MenuBarMode {
        switch preferred {
        case .automatic:
            return powerSource == .battery ? .battery : .ac
        case .ac, .battery:
            return preferred
        }
    }

    /// Menu bar title. `compact` drops labels when the notch is crowded.
    func menuBarText(mode: MenuBarMode, compact: Bool) -> String {
        switch resolvedMode(preferred: mode) {
        case .ac:
            if compact {
                return "\(voltageText) \(currentText) \(powerText)"
            }
            return "\(voltageText) \(currentText) \(powerText)"
        case .battery:
            if compact {
                return "\(cpuText) \(ramText) \(fan.rpm.map { String(format: "%.0f", $0) + "rpm" } ?? "—") \(temperatureText)"
            }
            return "CPU \(cpuText) RAM \(ramText) \(fanText) \(temperatureText)"
        case .automatic:
            return ""
        }
    }

    var menuBarAccessibilityLabel: String {
        "\(powerSource.label). Battery \(batteryText). Voltage \(voltageText), current \(currentText), power \(powerText). CPU \(cpuText), RAM \(ramText), fan \(fanText), temperature \(temperatureText)."
    }
}
