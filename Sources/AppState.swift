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

    init() {
        preferences = PreferencesStore()
        telemetry = TelemetryStore()
        thresholds = ThresholdController(preferences: preferences)

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
            .sink { [weak self] _ in self?.scanEFI() }
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
        guard !isScanning else { return }
        isScanning = true
        let path = preferences.efiFolderPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = ACPIInspector.inspect(savedEFIPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inspection = result
                self.isScanning = false
                if let root = result.efiRoot, self.preferences.efiFolderPath.isEmpty {
                    self.preferences.efiFolderPath = root.path
                }
            }
        }
    }

    // MARK: - Threshold sync (pola dari BatteryLenovoAssistent)

    /// Timer 3 detik + observer IOKit saat charger cabut/colok. Semua tulisan
    /// threshold dijalankan di background; tidak membanjiri EC karena adapter
    /// hanya menulis byte yang berbeda (WE1B + read-back RE1B).
    private func startThresholdSync() {
        thresholdTimer?.invalidate()
        let interval = min(max(preferences.thresholdReapplyInterval, 1.0), 30.0)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.reapplyThresholdQuietly()
        }
        RunLoop.main.add(timer, forMode: .common)
        thresholdTimer = timer

        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePowerSourceChange),
            name: .powerSourceDidChange, object: nil
        )
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

    func openFullGUI() {
        NSApp.setActivationPolicy(preferences.hideDockIcon ? .accessory : .regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.contentViewController != nil || window.title != "" {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .openFullGUI, object: nil)
    }
}

extension Notification.Name {
    static let openFullGUI = Notification.Name("com.systats.openFullGUI")
    static let powerSourceDidChange = Notification.Name("com.systats.powerSourceDidChange")
}
