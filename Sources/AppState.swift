import Foundation
import Combine
import AppKit
#if canImport(IOKit)
import IOKit
import IOKit.ps
#endif

/// State bersama untuk SwiftUI dan menu bar.
final class AppState: ObservableObject {
    let preferences: PreferencesStore
    let telemetry: TelemetryStore
    let thresholds: ThresholdController

    @Published private(set) var inspection = EFIInspection()
    @Published private(set) var isScanning = false
    @Published var selectedTab: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private var thresholdTimer: Timer?
    private var pendingForceApply: DispatchWorkItem?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var lastScannedPath: String?
    private var needsRescan = false

    init() {
        preferences = PreferencesStore()
        telemetry = TelemetryStore()
        thresholds = ThresholdController(preferences: preferences)

        // AppState HANYA mem-publish selectedTab / inspection / isScanning.
        // Preferences, telemetry, dan threshold TIDAK diteruskan ke sini: kalau
        // diteruskan, setiap ketikan, geseran slider, atau poll merender ulang
        // ContentView + TabView + semua tab. View yang butuh data itu mengamati
        // objeknya sendiri lewat @EnvironmentObject.

        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePowerSourceChange),
            name: .powerSourceDidChange, object: nil
        )

        restartPolling()
        startThresholdSync()

        preferences.$pollInterval
            .dropFirst()
            .sink { [weak self] interval in self?.restartPolling(interval: interval) }
            .store(in: &cancellables)

        preferences.$thresholdReapplyInterval
            .dropFirst()
            .sink { [weak self] _ in self?.startThresholdSync() }
            .store(in: &cancellables)

        preferences.$efiFolderPath
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] path in
                // Path hasil deteksi otomatis sudah dipindai; jangan scan dua kali.
                guard let self, path != self.lastScannedPath else { return }
                self.scanEFI()
            }
            .store(in: &cancellables)
    }

    deinit {
        thresholdTimer?.invalidate()
        pendingForceApply?.cancel()
        NotificationCenter.default.removeObserver(self)
        #if canImport(IOKit)
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        #endif
        YogaSMCBridge.shared.closeECConnection()
    }

    func restartPolling(interval: TimeInterval? = nil) {
        telemetry.start(interval: interval ?? preferences.pollInterval)
    }

    func scanEFI() {
        // Scan sedang jalan lalu path berubah: jangan dibuang diam-diam (hasil
        // lama akan basi) — jadwalkan scan ulang setelah yang berjalan selesai.
        guard !isScanning else {
            needsRescan = true
            return
        }
        isScanning = true
        let path = preferences.efiFolderPath
        lastScannedPath = path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = ACPIInspector.inspect(savedEFIPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inspection = result
                self.isScanning = false
                if let root = result.efiRoot, self.preferences.efiFolderPath.isEmpty {
                    self.lastScannedPath = root.path
                    self.preferences.efiFolderPath = root.path
                }
                if self.needsRescan {
                    self.needsRescan = false
                    self.scanEFI()
                }
            }
        }
    }

    // MARK: - Threshold sync (pola dari BatteryLenovoAssistent)

    /// Timer (default 3 detik) + observer IOKit saat charger cabut/colok. Semua
    /// tulisan threshold dijalankan di background dan HANYA aktif setelah
    /// pengguna sendiri berhasil menekan Apply (`thresholdAutoReapply`).
    /// Jalur Direct EC hanya menulis byte yang berbeda (WE1B + read-back RE1B).
    private func startThresholdSync() {
        thresholdTimer?.invalidate()
        let interval = min(max(preferences.thresholdReapplyInterval, 1.0), 30.0)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.reapplyThresholdQuietly()
        }
        RunLoop.main.add(timer, forMode: .common)
        thresholdTimer = timer

        // Observer didaftarkan SEKALI di init (dulu didaftarkan ulang setiap interval
        // diubah → handler dobel). Di sini hanya timer + run loop source IOKit.
        #if canImport(IOKit)
        if powerSourceRunLoopSource == nil {
            let source = IOPSNotificationCreateRunLoopSource({ _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .powerSourceDidChange, object: nil)
                }
            }, nil)?.takeRetainedValue()
            powerSourceRunLoopSource = source
            if let source = source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            }
        }
        #endif
    }

    private func reapplyThresholdQuietly() {
        // Jangan menyentuh hardware sebelum pengguna menekan Apply sendiri.
        guard thresholds.canAutoReapply else { return }
        let start = thresholds.startPercent
        let stop = thresholds.stopPercent
        Task { await thresholds.reapply(start: start, stop: stop) }
    }

    @objc private func handlePowerSourceChange() {
        telemetry.refresh()
        // EC perlu waktu "settle" setelah charger dicolok/dicabut.
        pendingForceApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reapplyThresholdQuietly()
        }
        pendingForceApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// Tampilkan (atau buat ulang) jendela utama. Dipakai tombol di popover
    /// menu bar, tombol "Open Dashboard", dan klik ikon Dock.
    func openFullGUI() {
        selectedTab = 0
        MainWindowController.shared.show()
    }
}

extension Notification.Name {
    static let openFullGUI = Notification.Name("com.systats.openFullGUI")
    static let powerSourceDidChange = Notification.Name("com.systats.powerSourceDidChange")
}
