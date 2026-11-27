import Foundation

/// Topics we look for while auditing EFI/ACPI definitions.
enum ACPICategory: String, CaseIterable, Identifiable {
    case battery
    case embeddedController
    case thermal
    case fan
    case smc
    case power
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .battery: return "Battery"
        case .embeddedController: return "Embedded Controller"
        case .thermal: return "Thermal"
        case .fan: return "Fan"
        case .smc: return "SMC"
        case .power: return "Power management"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .battery: return "battery.100.bolt"
        case .embeddedController: return "cpu"
        case .thermal: return "thermometer"
        case .fan: return "wind"
        case .smc: return "chip"
        case .power: return "bolt"
        case .other: return "doc.text"
        }
    }
}

enum ACPIFindingOrigin: String {
    case amlHeader = "AML table header"
    case amlStringScan = "AML heuristic string scan"
    case dslSource = "DSL source"
    case configPlist = "config.plist"
    case filesystem = "Filesystem"
}

/// A single detected device / method / table / kext. Findings are *definitions*,
/// not proof that macOS exposes a writable runtime interface.
struct ACPIFinding: Identifiable {
    let id = UUID()
    var category: ACPICategory
    var name: String
    var detail: String
    var sourceFile: String
    var origin: ACPIFindingOrigin

    var searchText: String { "\(name) \(detail) \(sourceFile)" }
}

struct ACPIFileInfo: Identifiable {
    let id = UUID()
    var url: URL
    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
    var sizeBytes: Int64 = 0
    var isReadable = false
    var tableSignature: String?
    var tableLength: Int?
    var oemID: String?
    var findings: [ACPIFinding] = []
    var errorMessage: String?

    var categorySummary: String {
        let set = Set(findings.map(\.category))
        guard !set.isEmpty else { return "No relevant tokens detected" }
        return set.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: ", ")
    }
}

struct KextStatus: Identifiable {
    let id = UUID()
    var name: String
    var bundlePath: String
    var isEnabled: Bool?   // nil = config.plist unavailable, enabled state unknown
    var note: String

    var stateLabel: String {
        switch isEnabled {
        case .some(true): return "Enabled"
        case .some(false): return "Disabled"
        case .none: return "Unknown"
        }
    }
}

enum CapabilityStatus: String {
    case available
    case restricted
    case unavailable
    case unknown

    var label: String {
        switch self {
        case .available: return "Available"
        case .restricted: return "Restricted"
        case .unavailable: return "Unavailable"
        case .unknown: return "Unknown"
        }
    }
}

/// Runtime write capability assessment. Kept separate from ACPI file audit on
/// purpose: a method existing in an AML file does NOT mean it can be called
/// from user space on macOS.
struct ThresholdCapability {
    var adapterID: String = "none"
    var displayName: String = "No adapter"
    var status: CapabilityStatus = .unknown
    var canRead = false
    var canWrite = false
    var reasons: [String] = []
    var evidence: [String] = []
    var requiredPrivileges: String?

    var summary: String {
        if reasons.isEmpty { return status.label }
        return reasons.first ?? status.label
    }

    /// Bahasa sehari-hari untuk user awam. Detail teknis tetap ada di
    /// `summary`/`reasons`/`evidence` untuk dibuka di "Detail teknis".
    var humanTitle: String {
        switch status {
        case .available: return "Batas cas bisa diatur"
        case .restricted: return "Batas cas belum bisa diatur"
        case .unavailable: return "Tidak tersedia di perangkat ini"
        case .unknown: return "Belum terdeteksi"
        }
    }

    var humanDetail: String {
        switch status {
        case .available:
            return "YogaSMC sudah aktif. Tombol Apply akan memakai jalur ini."
        case .restricted:
            return "Status baterai terbaca, tapi belum ada jalur resmi untuk mengatur batas cas."
        case .unavailable:
            return "Perangkat pendukung tidak ditemukan di mesin ini."
        case .unknown:
            return "Pemeriksaan EFI berjalan otomatis. Bila tetap tidak terdeteksi, siapkan helper di Preferences."
        }
    }
}

struct EFIInspection {
    var inspectedAt: Date = Date()
    var efiRoot: URL?
    var acpiDirectories: [URL] = []
    var files: [ACPIFileInfo] = []
    var kexts: [KextStatus] = []
    var capability = ThresholdCapability()
    var diagnostics: [String] = []

    var totalFindings: Int { files.reduce(0) { $0 + $1.findings.count } }

    var relevantFiles: [ACPIFileInfo] {
        files.filter { !$0.findings.isEmpty }
    }
}
