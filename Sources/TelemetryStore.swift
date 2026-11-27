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
    @Published private(set) var isRefreshing = false

    private let queue = DispatchQueue(label: "com.systats.telemetry", qos: .utility)
    private var timer: Timer?
    private var interval: TimeInterval = 2.0
    private let lock = NSLock()

    deinit { timer?.invalidate() }

    func start(interval: TimeInterval) {
        stop()
        let clamped = Swift.min(Swift.max(interval, 1.0), 10.0)
        lock.lock()
        self.interval = clamped
        lock.unlock()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        lock.lock()
        let busy = isRefreshing
        lock.unlock()
        guard !busy else { return }
        lock.lock()
        isRefreshing = true
        lock.unlock()

        queue.async { [weak self] in
            let sample = TelemetryCollector.collect()
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot = sample
                self.lock.lock()
                self.isRefreshing = false
                self.lock.unlock()
            }
        }
    }
}
