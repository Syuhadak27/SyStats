import Foundation

/// Modular write adapters. Setiap adapter jujur tentang apa yang benar-benar
/// bisa dilakukan; kegagalan tidak pernah dilaporkan sebagai sukses.
protocol ThresholdAdapting {
    var id: String { get }
    var displayName: String { get }
    var detail: String { get }
    func read(preferences: PreferencesStore) async -> ThresholdConfiguration?
    func write(start: Int, stop: Int, preferences: PreferencesStore) async -> ThresholdOperationResult
    func statusDescription(preferences: PreferencesStore) async -> String?
}

extension ThresholdAdapting {
    func statusDescription(preferences: PreferencesStore) async -> String? { nil }
}

// MARK: - YogaSMC / ThinkVPC (jalur utama, sesuai repo referensi)

/// Threshold YogaSMC 1.5.3 memakai properti IOUserClient ThinkVPC:
/// `setCMstart` → ACPI `BCCS`, `setCMstop` → `BCSS`. BUKAN SMC key.
/// Opsi lanjutan menulis byte EC langsung lewat `WE1B` lalu verifikasi `RE1B`.
struct ThinkVPCAdapter: ThresholdAdapting {
    let id = "thinkVPC"
    let displayName = "YogaSMC / ThinkVPC"
    let detail = "ACPI BCCS/BCSS via ThinkVPC · opsional EC langsung (WE1B + RE1B read-back)"

    func read(preferences: PreferencesStore) async -> ThresholdConfiguration? {
        // Nilai BCTG/BCSG mentah tidak dipakai sebagai UI: pasangan start/stop
        // belum bisa dipastikan dari binary kext. Lihat statusDescription().
        nil
    }

    func statusDescription(preferences: PreferencesStore) async -> String? {
        guard let raw = YogaSMCBridge.shared.rawBatteryStatus() else {
            return "BAT_PRIMARY belum bisa dibaca dari ThinkVPC."
        }
        let text = raw.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        return "BAT_PRIMARY (diagnostik): \(text). Byte rendah = persentase, byte tinggi = flag; pemetaan BCTG/BCSG belum diverifikasi — UI tetap menampilkan nilai yang diinginkan."
    }

    func write(start: Int, stop: Int, preferences: PreferencesStore) async -> ThresholdOperationResult {
        if let validation = ThresholdValidation.message(start: start, stop: stop) {
            return ThresholdOperationResult(success: false, message: validation)
        }
        let enabled = preferences.thresholdEnabled
        let battery = min(max(preferences.batteryIndex, 0), 2)
        // YogaSMCPane mengirim 0 untuk stop 100%.
        let ysmcStop = stop >= 100 ? 0 : stop
        var props: [String: Any] = [
            "Battery": battery,
            "setCMstart": enabled ? start : 0,
            "setCMstop": enabled ? ysmcStop : 0,
        ]
        if !enabled { props["setCMInhibitCharge"] = 0 }

        var details: [String] = [
            "Battery=\(battery) dikirim lebih dulu (0=ANY, 1=PRIMARY, 2=SECONDARY).",
            enabled
                ? "ACPI BCCS(start=\(start)%) / BCSS(stop=\(stop)% → dikirim \(ysmcStop)) via ThinkVPC."
                : "Threshold dimatikan: start=0, stop=0, inhibit=0 (pengisian penuh normal).",
        ]

        do {
            try YogaSMCBridge.shared.setProperties([
                ["Battery": battery],
                props,
            ])
        } catch {
            return ThresholdOperationResult(
                success: false,
                message: "Gagal menulis ke ThinkVPC.",
                details: details + [(error as? LocalizedError)?.errorDescription ?? error.localizedDescription]
            )
        }

        var verified = false
        if preferences.ecDirectEnabled {
            let direct = applyDirectEC(
                start: start, stop: stop, enabled: enabled, preferences: preferences,
                details: &details
            )
            verified = direct.verified
            if !direct.attempted {
                details.append("Direct EC aktif tetapi offset Start/Stop belum diisi — tidak ada byte EC yang ditulis.")
            }
        } else {
            details.append("Direct EC (WE1B) nonaktif. Perubahan lewat SMI firmware BCCS/BCSS; verifikasi byte EC tidak tersedia.")
        }

        if let raw = YogaSMCBridge.shared.rawBatteryStatus() {
            details.append("BAT_PRIMARY: \(raw.map { "\($0.key)=\($0.value)" }.joined(separator: " ")) (diagnostik saja).")
        }

        return ThresholdOperationResult(
            success: true,
            verified: verified,
            message: verified ? "Threshold diterapkan dan terverifikasi di EC." : "Threshold diterapkan ke ThinkVPC (belum terverifikasi di EC).",
            details: details
        )
    }

    private func applyDirectEC(
        start: Int, stop: Int, enabled: Bool,
        preferences: PreferencesStore, details: inout [String]
    ) -> (attempted: Bool, verified: Bool) {
        func valid(_ value: Int) -> UInt8? {
            (1...0x99).contains(value) ? UInt8(value) : nil
        }
        guard let startOffset = valid(preferences.ecStartOffset),
              let stopOffset = valid(preferences.ecStopOffset) else {
            return (false, false)
        }

        let desiredStart = UInt8(enabled ? min(max(start, 0), 100) : 0)
        let desiredStop = UInt8(enabled ? (stop >= 100 ? 0 : min(max(stop, 0), 100)) : 0)
        let bridge = YogaSMCBridge.shared

        func writeIfNeeded(_ offset: UInt8, _ desired: UInt8, _ label: String) -> Bool {
            do {
                let before = try bridge.readECByte(offset)
                if before == desired {
                    details.append(String(format: "RE1B %@ 0x%02X sudah 0x%02X (tidak ditulis ulang).", label, offset, desired))
                    return true
                }
                try bridge.writeECByte(offset, desired)
                let after = try bridge.readECByte(offset)
                let ok = after == desired
                details.append(String(
                    format: "WE1B %@ 0x%02X ← 0x%02X (sebelum 0x%02X, read-back 0x%02X)%@",
                    label, offset, desired, before, after, ok ? "" : " [MISMATCH]"
                ))
                return ok
            } catch {
                details.append("[BatteryEC] \(label) gagal: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                return false
            }
        }

        let startOK = writeIfNeeded(startOffset, desiredStart, "start")
        let stopOK = writeIfNeeded(stopOffset, desiredStop, "stop")
        var inhibitOK = true
        if let inhibit = valid(preferences.ecInhibitOffset) {
            inhibitOK = writeIfNeeded(inhibit, 0, "inhibit")
        }
        return (true, startOK && stopOK && inhibitOK)
    }
}

// MARK: - VirtualSMC (read-only, jujur)

/// VirtualSMC/SMCBatteryManager mengekspos status baterai, tetapi tidak ada
/// path write threshold yang terdokumentasi. Tidak pernah berpura-pura menulis.
struct VirtualSMCAdapter: ThresholdAdapting {
    let id = "virtualSMC"
    let displayName = "VirtualSMC (read-only)"
    let detail = "Hanya status baterai. Tidak ada jalur BCCS/BCSS tanpa YogaSMC."

    func read(preferences: PreferencesStore) async -> ThresholdConfiguration? { nil }

    func write(start: Int, stop: Int, preferences: PreferencesStore) async -> ThresholdOperationResult {
        ThresholdOperationResult(
            success: false,
            message: "VirtualSMC tidak memiliki jalur tulis threshold.",
            details: [
                "Gunakan YogaSMC/ThinkVPC (ACPI BCCS/BCSS) atau helper eksternal.",
                "Tidak ada nilai yang diubah.",
            ]
        )
    }
}

// MARK: - External helper (user-supplied tool)

/// Menjalankan executable dengan argumen `<start%> <stop%>` tanpa shell.
/// Exit code bukan 0 selalu dilaporkan gagal beserta stdout/stderr.
struct ExternalHelperAdapter: ThresholdAdapting {
    let id = "externalHelper"
    let displayName = "External helper"
    let detail = "Menjalankan: <path> <start%> <stop%>"

    func read(preferences: PreferencesStore) async -> ThresholdConfiguration? { nil }

    func write(start: Int, stop: Int, preferences: PreferencesStore) async -> ThresholdOperationResult {
        if let message = ThresholdValidation.message(start: start, stop: stop) {
            return ThresholdOperationResult(success: false, message: message)
        }
        let path = (preferences.helperCommandPath as NSString).expandingTildeInPath
        guard !path.isEmpty else {
            return ThresholdOperationResult(
                success: false,
                message: "Helper belum dikonfigurasi.",
                details: ["Isi path executable di Menu Bar & Preferences → Advanced."]
            )
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return ThresholdOperationResult(
                success: false,
                message: "Helper tidak bisa dieksekusi.",
                details: [path, "Jalankan chmod +x pada helper tersebut."]
            )
        }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = [String(start), String(stop)]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
                process.waitUntilExit()
                let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let succeeded = process.terminationStatus == 0
                var details = ["Exit status: \(process.terminationStatus)"]
                if !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    details.append("stdout: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                if !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    details.append("stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                return ThresholdOperationResult(
                    success: succeeded,
                    message: succeeded ? "Helper melaporkan sukses." : "Helper gagal — lihat detail.",
                    details: details
                )
            } catch {
                return ThresholdOperationResult(
                    success: false,
                    message: "Gagal menjalankan helper: \(error.localizedDescription)",
                    details: [path]
                )
            }
        }.value
    }
}
