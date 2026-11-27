import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(IOKit)
import IOKit
#endif

/// Builds an EFI/ACPI audit. Strictly read-first: files are opened for reading
/// only, and the result separates "definitions found on disk" from "runtime
/// write capability of macOS".
enum ACPIInspector {
    private static let relevantKexts = [
        "VirtualSMC.kext", "SMCBatteryManager.kext", "SMCProcessor.kext",
        "SMCSuperIO.kext", "YogaSMC.kext", "YogaSMC-VENTURA.kext",
        "YogaSMC-SEQUOIA.kext", "ECEnabler.kext", "VoodooSMBus.kext",
    ]

    static func inspect(savedEFIPath: String?) -> EFIInspection {
        var result = EFIInspection()
        guard let root = EFIDetector.detectRoot(savedPath: savedEFIPath) else {
            result.diagnostics.append("EFI folder not found. Use “Choose…” in the Inspector tab to select one (e.g. /Volumes/EFI/EFI).")
            result.capability = ThresholdCapability(
                adapterID: "none", displayName: "No EFI folder", status: .unknown,
                reasons: ["Select an EFI folder to assess threshold interfaces."]
            )
            return result
        }
        result.efiRoot = root
        result.acpiDirectories = EFIDetector.acpiDirectories(for: root)
        if result.acpiDirectories.isEmpty {
            result.diagnostics.append("No ACPI folder found under \(root.path). Expected OC/ACPI, APPLE/ACPI or ACPI.")
        }

        for directory in result.acpiDirectories {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
            )) ?? []
            let tableFiles = files.filter { ["aml", "dsl"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

            for url in tableFiles {
                var info = ACPIFileInfo(url: url)
                guard FileManager.default.isReadableFile(atPath: url.path) else {
                    info.isReadable = false
                    info.errorMessage = "File is not readable (permissions)."
                    result.files.append(info)
                    continue
                }
                do {
                    let data = try Data(contentsOf: url)
                    info.isReadable = true
                    info.sizeBytes = Int64(data.count)
                    if info.fileExtension == "aml" {
                        if let header = ACPIParser.parseHeader(data) {
                            info.tableSignature = header.signature
                            info.tableLength = header.length
                            info.oemID = header.oemID
                            info.findings.append(ACPIFinding(
                                category: .other,
                                name: "Table \(header.signature)",
                                detail: "Length \(header.length) bytes, rev \(header.revision), OEM \(header.oemID) \(header.oemTableID)".trimmingCharacters(in: .whitespaces),
                                sourceFile: info.name,
                                origin: .amlHeader
                            ))
                        }
                        info.findings.append(contentsOf: ACPIParser.findings(inAML: data, fileName: info.name))
                    } else {
                        let text = String(data: data, encoding: .utf8)
                            ?? String(data: data, encoding: .isoLatin1) ?? ""
                        info.findings.append(contentsOf: ACPIParser.findings(inDSL: text, fileName: info.name))
                    }
                } catch {
                    info.errorMessage = error.localizedDescription
                    result.diagnostics.append("Could not read \(info.name): \(error.localizedDescription)")
                }
                result.files.append(info)
            }
        }

        result.kexts = readKextStates(from: root, diagnostics: &result.diagnostics)
        result.capability = assessCapability(
            kexts: result.kexts,
            files: result.files,
            diagnostics: &result.diagnostics
        )
        return result
    }

    // MARK: - Kext state from config.plist (read-only)

    private static func readKextStates(from root: URL, diagnostics: inout [String]) -> [KextStatus] {
        guard let config = EFIDetector.configURL(for: root),
              let data = try? Data(contentsOf: config),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let kernel = plist["Kernel"] as? [String: Any],
              let additions = kernel["Add"] as? [[String: Any]] else {
            diagnostics.append("config.plist not readable: kext Enabled states are unknown (filesystem presence only).")
            return relevantKexts.map {
                KextStatus(name: $0, bundlePath: $0, isEnabled: nil, note: "Enabled state unknown")
            }
        }

        var statuses: [KextStatus] = []
        for name in relevantKexts {
            var found = false
            for item in additions {
                let path = item["BundlePath"] as? String ?? ""
                guard (path as NSString).lastPathComponent == name else { continue }
                found = true
                let enabled: Bool
                if let value = item["Enabled"] as? Bool { enabled = value }
                else if let value = item["Enabled"] as? NSNumber { enabled = value.boolValue }
                else { enabled = false }
                statuses.append(KextStatus(
                    name: name,
                    bundlePath: path,
                    isEnabled: enabled,
                    note: enabled ? "Listed and enabled in config.plist" : "Present but disabled in config.plist"
                ))
            }
            if !found {
                statuses.append(KextStatus(name: name, bundlePath: name, isEnabled: false, note: "Not enabled in config.plist"))
            }
        }
        return statuses
    }

    // MARK: - Runtime write capability assessment

    private static func assessCapability(
        kexts: [KextStatus], files: [ACPIFileInfo], diagnostics: inout [String]
    ) -> ThresholdCapability {
        let isEnabled: (String) -> Bool = { name in
            kexts.first { $0.name == name }?.isEnabled == true
        }
        let yogaEnabled = isEnabled("YogaSMC.kext") || isEnabled("YogaSMC-VENTURA.kext") || isEnabled("YogaSMC-SEQUOIA.kext")
        let batteryManager = isEnabled("SMCBatteryManager.kext")
        let virtualSMC = isEnabled("VirtualSMC.kext")
        let ecEnabler = isEnabled("ECEnabler.kext")

        var evidence: [String] = []
        if yogaEnabled { evidence.append("YogaSMC diaktifkan di config.plist.") }
        if batteryManager { evidence.append("SMCBatteryManager aktif: status baterai terbaca, bukan penulis threshold.") }
        if virtualSMC { evidence.append("VirtualSMC aktif: SMC key di-emulasi; B0St/B0Sp/B0En/BCLM bukan jalur threshold.") }
        if ecEnabler { evidence.append("ECEnabler aktif: akses field EC lebih baik, tapi tulis EC userspace tetap butuh kext/user client.") }

        let methodNames = files.flatMap(\.findings).map(\.name)
        if methodNames.contains(where: { $0 == "BCCS" || $0 == "BCSS" || $0 == "WE1B" || $0 == "RE1B" }) {
            evidence.append("AML berisi token BCCS/BCSS/WE1B/RE1B — definisi, bukti runtime tetap dari IORegistry.")
        }

        // Bukti runtime lebih kuat daripada config.plist: service ThinkVPC
        // benar-benar terpasang atau tidak.
        let thinkVPCLive = YogaSMCBridge.isThinkVPCAvailable()
        if thinkVPCLive {
            evidence.append("ThinkVPC ditemukan di IORegistry (runtime): BCCS/BCSS via properti IOUserClient tersedia.")
        }

        if thinkVPCLive {
            return ThresholdCapability(
                adapterID: "thinkVPC", displayName: "YogaSMC / ThinkVPC",
                status: .available, canRead: true, canWrite: true,
                reasons: ["ThinkVPC aktif. Tulis via setCMstart/setCMstop → ACPI BCCS/BCSS; opsional WE1B + RE1B."],
                evidence: evidence,
                requiredPrivileges: "Akses IOKit ke service ThinkVPC (app tidak disandbox)."
            )
        }
        if yogaEnabled {
            diagnostics.append("YogaSMC aktif di config.plist tetapi service ThinkVPC belum ada di IORegistry. Cek ioreg -lw0 | grep -i ThinkVPC dan SSDT-YVPC.")
            return ThresholdCapability(
                adapterID: "thinkVPC", displayName: "YogaSMC / ThinkVPC",
                status: .restricted, canRead: true, canWrite: false,
                reasons: ["Kext aktif tetapi ThinkVPC belum terpasang saat runtime — write tidak akan berhasil."],
                evidence: evidence,
                requiredPrivileges: "Akses IOKit ke service ThinkVPC."
            )
        }
        if batteryManager || virtualSMC {
            return ThresholdCapability(
                adapterID: "externalHelper", displayName: "External helper diperlukan",
                status: .restricted, canRead: true, canWrite: false,
                reasons: ["Status baterai terbaca, tetapi tidak ada jalur BCCS/BCSS. Siapkan helper eksternal di Preferences."],
                evidence: evidence,
                requiredPrivileges: "Helper dengan hak akses sesuai perangkat."
            )
        }
        diagnostics.append("Tidak ada adapter threshold yang terdeteksi. Tulis EC langsung dari userspace diblokir macOS tanpa kext/helper.")
        return ThresholdCapability(
            adapterID: "externalHelper", displayName: "External helper diperlukan",
            status: .unknown, canRead: false, canWrite: false,
            reasons: ["Tidak ada bukti YogaSMC/ThinkVPC. Isi path helper di Preferences untuk mencoba write."],
            evidence: evidence,
            requiredPrivileges: "Helper dengan hak akses sesuai perangkat."
        )
    }
}
