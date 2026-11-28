import Foundation
import Combine

/// Combines all collectors into a single sample. Runs off the main thread.
enum TelemetryCollector {
    static func collect() -> TelemetrySnapshot {
        let power = PowerSourceReader.read()
        var snapshot = TelemetrySnapshot()
        snapshot.powerSource = power.source
        snapshot.battery = power.battery
        snapshot.electrical = power.electrical
        snapshot.cpuUsagePercent = SystemMonitor.cpuUsagePercent()
        snapshot.ramUsagePercent = SystemMonitor.ramUsagePercent()
        snapshot.fan = SensorReader.readFan()
        snapshot.thermal = SensorReader.readTemperature()
        snapshot.diagnostics.append(contentsOf: power.diagnostics)

        if snapshot.fan.rpm == nil {
            snapshot.diagnostics.append("Fan RPM: SMC F0Ac/F1Ac not readable (SMCSuperIO/YogaSMC may use different keys).")
        }
        if snapshot.thermal.cpuTemperatureC == nil {
            snapshot.diagnostics.append("CPU temperature: SMC TC0D/TC0P/TN0P not readable on this machine.")
        }
        if snapshot.cpuUsagePercent == nil {
            snapshot.diagnostics.append("CPU usage: waiting for a second Mach sample.")
        }
        return snapshot
    }
}

/// Main-thread observable store. Polling happens on a utility serial queue so
/// the menu bar timer never blocks the main thread with IOKit/SMC calls.
final class TelemetryStore: ObservableObject {
    @Published private(set) var snapshot = TelemetrySnapshot()

    private let queue = DispatchQueue(label: "com.systats.telemetry", qos: .utility)
    private var timer: Timer?
    /// Hanya disentuh dari main thread (refresh() dan callback-nya selalu di main),
    /// jadi tidak perlu lock. SENGAJA bukan @Published: dulu flag ini di-publish
    /// dan berganti true/false di setiap poll, sehingga setiap view yang mengamati
    /// store dirender ulang DUA kali per poll (sekali untuk flag, sekali untuk data).
    private var isRefreshing = false

    deinit { timer?.invalidate() }

    func start(interval: TimeInterval) {
        stop()
        let clamped = Swift.min(Swift.max(interval, 1.0), 10.0)
        refresh()
        let newTimer = Timer(timeInterval: clamped, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Toleransi memberi sistem keleluasaan menggabung wake-up (hemat CPU).
        newTimer.tolerance = clamped * 0.1
        // Mode .default (bukan .common): selama pengguna scroll / menggeser slider
        // timer berhenti sejenak, jadi tidak ada render ulang yang menyela gesture.
        RunLoop.main.add(newTimer, forMode: .default)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Harus dipanggil dari main thread.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        queue.async { [weak self] in
            let sample = TelemetryCollector.collect()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.snapshot = sample
            }
        }
    }
}
