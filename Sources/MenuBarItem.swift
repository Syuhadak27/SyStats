import Foundation

/// Satu entri yang bisa ditampilkan user di menu bar atas.
///
/// `label` adalah teks bebas milik user (boleh dikosongkan). Label kosong
/// berarti item TETAP aktif dan nilainya tetap tampil — hanya labelnya yang
/// disembunyikan. `enabled` mengontrol apakah item ikut dirender atau tidak.
struct MenuBarItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case voltage
        case current
        case power
        case cpu
        case ram
        case fan
        case temperature
        case battery

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .voltage: return "Voltage (V)"
            case .current: return "Current (A)"
            case .power: return "Power (W)"
            case .cpu: return "CPU (%)"
            case .ram: return "RAM (%)"
            case .fan: return "Fan (RPM)"
            case .temperature: return "Temperature (°C)"
            case .battery: return "Battery (%)"
            }
        }

        var symbol: String {
            switch self {
            case .voltage, .power: return "bolt.fill"
            case .current: return "arrow.left.arrow.right"
            case .cpu: return "cpu"
            case .ram: return "memorychip"
            case .fan: return "wind"
            case .temperature: return "thermometer"
            case .battery: return "battery.75"
            }
        }

        /// Label bawaan saat item dibuat / preset diterapkan.
        var defaultLabel: String {
            switch self {
            case .voltage: return "V"
            case .current: return "A"
            case .power: return "W"
            case .cpu: return "CPU"
            case .ram: return "RAM"
            case .fan: return "RPM"
            case .temperature: return "°C"
            case .battery: return "BAT"
            }
        }
    }

    var id: UUID
    var kind: Kind
    var enabled: Bool
    /// Teks bebas user. Kosong = sembunyikan label, nilai tetap tampil.
    var label: String

    init(id: UUID = UUID(), kind: Kind, enabled: Bool = true, label: String? = nil) {
        self.id = id
        self.kind = kind
        self.enabled = enabled
        self.label = label ?? kind.defaultLabel
    }

    /// Decode retro-kompatibel: kalau suatu field tidak ada, pakai default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(Kind.self, forKey: .kind)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? kind.defaultLabel
    }

    static func preset(for mode: MenuBarMode) -> [MenuBarItem] {
        switch mode {
        case .ac:
            return [.init(kind: .voltage), .init(kind: .current), .init(kind: .power)]
        case .battery:
            return [.init(kind: .cpu), .init(kind: .ram), .init(kind: .fan), .init(kind: .temperature)]
        case .automatic:
            // Automatic mengikuti sumber daya: awalnya pakai preset AC, tapi
            // daftar ini tetap bisa diubah bebas oleh user.
            return preset(for: .ac)
        }
    }
}
