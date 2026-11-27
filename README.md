# SyStats

Aplikasi desktop native macOS (SwiftUI + AppKit `NSStatusItem`) untuk Hackintosh:
- **Audit EFI/ACPI read-only** pada folder EFI (OpenCore / APPLE).
- **Menu bar dinamis**: saat charger terpasang menampilkan `V A W`, saat baterai menampilkan `CPU% RAM% RPM °C`.
- **Kontrol charge threshold** Start/Stop dengan arsitektur adapter yang jujur (tidak pernah mengklaim sukses jika interface menolak).

> Build dan release sepenuhnya via GitHub Actions pada runner macOS. Tidak ada build lokal.

---

## 1. Struktur & aset

```
.
├── Sources/              # semua file Swift (flat, satu folder saja)
├── Assets.xcassets/      # AppIcon + MenuBarIcon
├── Config/Info.plist     # Info.plist manual (dipakai project.yml)
├── project.yml           # spesifikasi XcodeGen
├── .github/workflows/    # build & release
└── EFI/                  # REFERENSI LOKAL SAJA — diabaikan git, tidak ikut commit/push
```

| Aset | Keterangan |
|---|---|
| `icon.png` | Ikon aplikasi (AppIcon). |
| `menu_bar.png` | **Tidak dibuat glif khusus** — langsung diturunkan dari `icon.png` (bagian terang diekstrak sebagai alpha), 44×44 px @2x, dirender sebagai *template image* agar tajam di menu bar terang/gelap. |

Ganti ikon cukup dengan menimpa `icon.png` lalu regenerate `menu_bar.png`, atau pilih path custom di tab **Menu Bar & Preferences → Assets**. Aplikasi tidak crash bila path berubah; fallback ke aset bundle.

Folder `EFI/` hanya contoh referensi dan **sengaja tidak ikut version control** (lihat `.gitignore`).

---

## 2. Arsitektur kode

Semua kode ada di satu folder `Sources/` agar ringkas:
- `SyStatsApp.swift`, `AppEnvironment.swift`, `AppState.swift` — entry & state bersama.
- `AppDelegate.swift`, `MenuBarController.swift`, `MainWindowController.swift` — jembatan AppKit (`NSStatusItem`, popover, jendela utama yang bisa dibuka ulang setelah ditutup).
- `Telemetry*.swift`, `SMCReader.swift`, `PowerSourceReader.swift`, `SystemMonitor.swift`, `SensorReader.swift` — pembacaan sensor.
- `ACPIInspector.swift`, `ACPIParser.swift`, `EFIDetector.swift` — audit EFI (read-only).
- `YogaSMCBridge.swift`, `ThresholdAdapters.swift`, `ThresholdController.swift` — jembatan ThinkVPC/EC + adapter write threshold.
- `DashboardView.swift`, `InspectorView.swift`, `PreferencesView.swift`, `MenuBarPopoverView.swift`, `UIComponents.swift`, dll — GUI.

Pemisahan penting:
- **Audit (baca)**: `ACPIInspector` hanya membaca `.aml`/`.dsl` dan `config.plist`. File EFI tidak pernah ditulis/ditimpa.
- **Runtime write**: `ThresholdController` → `ThresholdAdapting`. Method ACPI yang ada di AML **tidak** otomatis bisa dipanggil dari userspace macOS; status ini ditampilkan terpisah di GUI.

---

## 3. Deteksi EFI & scan ACPI

`EFIDetector` mencoba (berurutan): path tersimpan → `/Volumes/EFI/EFI` → `/Volumes/EFI` → `/Volumes/ESP/EFI` → `/Volumes/ESP` → `~/Desktop/EFI` → `~/EFI` → `EFI` relatif.

Folder ACPI yang dipindai: `EFI/OC/ACPI`, `EFI/APPLE/ACPI`, `EFI/ACPI` (semua yang ada).

Untuk setiap `.aml`: header ACPI 36 byte diparse persis (signature, length, revision, OEMID, OEMTableID), lalu **heuristic ASCII token scan** (AML NamePath menyimpan segmen ASCII 4 karakter). Untuk `.dsl`: regex deklarasi `Device/Method/Name/OperationRegion/Field`. Kategori: battery, EC, thermal, fan, SMC, power management. Setiap temuan diberi label sumbernya.

`config.plist` dibaca untuk mengetahui kext yang benar-benar **Enabled** (VirtualSMC, SMCBatteryManager, SMCProcessor, SMCSuperIO, YogaSMC, ECEnabler, VoodooSMBus). Jika tidak terbaca, status **Unknown**, bukan dikira-kira.

---

## 4. Telemetri & keterbatasan jujur

| Data | Sumber | Catatan |
|---|---|---|
| Baterai %, charging, cycle, health | `IOPowerSources` | API publik macOS |
| Voltage / Current / Power | `IOPowerSources` bila tersedia, fallback SMC `VDCR`/`VDDR`, `IDCR`/`IB0R` | Banyak Hackintosh tidak mengeksposnya → tampil `—` + diagnostik, **tanpa data palsu** |
| CPU % | `host_statistics(HOST_CPU_LOAD_INFO)` | Delta antar sampling |
| RAM % | `host_statistics64(HOST_VM_INFO64)` | active + wired + compressed / total |
| Fan RPM | SMC `FNum`, `F0Ac`…`F4Ac` | Bergantung SMCSuperIO/YogaSMC |
| Suhu °C | SMC `TC0D`, `TC0P`, `TN0P`, `TC0c` | Umum di Intel Mac; tidak di Apple Silicon |

Pembacaan SMC/IOKit dijalankan di queue utility, bukan di callback timer main thread.

---

## 5. Charge threshold — mengikuti pola BatteryLenovoAssistent

Mekanisme diadaptasi dari audit repo [Syuhadak27/BatteryLenovoAssistent](https://github.com/Syuhadak27/BatteryLenovoAssistent) (YogaSMC 1.5.3). **Threshold bukan SMC key** (`B0St/B0Sp/B0En/BCLM` bukan jalur yang benar).

### Jalur utama — YogaSMC / ThinkVPC
- Cari service `ThinkVPC` di IORegistry (bukan hanya mengandalkan `config.plist`).
- Kirim properti IOUserClient secara **berurutan**:
  1. `{"Battery": 1}` — 0=ANY, 1=PRIMARY, 2=SECONDARY (urutan penting karena `NSDictionary` tidak terurut).
  2. `{"Battery": 1, "setCMstart": <start>, "setCMstop": <stop>}` → `ThinkVPC::setPropertiesGated()` → ACPI **`BCCS`/`BCSS`** → SMI/EC.
- Fallback: `IOServiceOpen` + `IOConnectSetCFProperties`.
- `stop = 100` dikirim sebagai `0` (sesuai YogaSMCPane). Saat threshold dimatikan: `start=0`, `stop=0`, `setCMInhibitCharge=0`.
- Status mentah `BAT_PRIMARY` (`BCTG`, `BCSG`, …) hanya untuk diagnostik; pasangan start/stop tidak dipakai sebagai UI karena pemetaannya tidak bisa dipastikan dari binary.

### Opsi lanjutan — Direct EC (default MATI)
- `YogaSMCUserClient` selector 0=open, 2=`readEC(offset)`, 3=`writeEC(offset,byte)` → method ACPI `RE1B`/`WE1B` dari `SSDT-EC.aml`.
- Offset diisi manual dalam hex `0x01–0x99` lewat **Menu Bar & Preferences → Advanced**. **Jangan menebak offset**; salah offset bisa mengubah fan/LED/sleep.
- Byte hanya ditulis bila berbeda, lalu diverifikasi dengan `RE1B`. Status GUI: **Applied & verified** vs **Applied (unverified)**.

### Realtime
- Timer reapply (default 3 detik, bisa diatur) + observer `IOPSNotificationCreateRunLoopSource` saat charger dicabut/dicolok, dengan debounce 2 detik agar EC sempat settle.
- Semua akses IOKit dijalankan di background; helper eksternal **tidak** dipanggil berulang oleh timer.

### Adapter lain
- **VirtualSMC**: read-only, jujur menolak write.
- **External helper**: `<path> <start%> <stop%>` tanpa shell; exit bukan 0 = gagal.

Validasi: 0–100%, `stop > start`, gap minimal 5%, slider langkah 5%. App **tidak disandbox** agar akses IOKit ke service kext diizinkan.

---

## 6. Build & Release via GitHub Actions

Workflow: `.github/workflows/build-release.yml` (runner `macos-latest`). Deployment target: **macOS 13.0**. Hasil build **universal** (Intel `x86_64` + Apple Silicon `arm64`) dan **ad-hoc signed**.

- Push `main`/`master`, PR, atau `workflow_dispatch` → build Release + upload artifact (`SyStats-<tag>.zip`, `SyStats-<tag>.dmg`, `SHA256SUMS.txt`).
- Push tag `v*` (mis. `v1.0.0`) → semua file di atas ikut dipublikasikan sebagai **GitHub Release**.
- Jika build gagal, log lengkap tersedia sebagai artifact `xcodebuild-log-*` dan ringkasan error muncul di tab *Summary*.

Langkah CI: `xcodegen generate --spec project.yml --project .` → `xcodebuild -scheme SyStats -configuration Release ARCHS="x86_64 arm64"` → verifikasi bundle → `codesign --sign -` (ad-hoc) → `ditto` zip + `hdiutil` dmg.

> Artifact GitHub membuang permission file, jadi `.app` tidak pernah diunggah mentah — selalu dibungkus zip/dmg dulu.

### Cara membuka (tanpa Terminal)

1. Unduh `.dmg` (atau `.zip`), seret **SyStats.app** ke **Applications**.
2. **Klik kanan** SyStats.app → **Open** → **Open**. Cukup sekali.
3. macOS 15 (Sequoia) ke atas: jika ditolak, buka **System Settings → Privacy & Security**, gulir ke bawah, klik **Open Anyway** di samping SyStats.

(Opsional, hanya jika masih diblokir: `xattr -cr "/Applications/SyStats.app"`.)

---

## 7. Catatan keamanan

- EFI diperlakukan **read-first**: tidak ada kode yang menulis `.aml`/`.dsl`/`config.plist`, dan folder EFI tidak ikut commit.
- SMC write hanya terjadi setelah tombol **Apply** ditekan pada adapter yang dipilih pengguna.
- Semua asumsi key SMC/ACPI terdokumentasi di komentar kode dan di GUI sebagai diagnostik.
- Preview menu bar di tab Preferences memakai telemetri aktual pada mode paksa, bukan angka contoh yang disajikan sebagai data live.
