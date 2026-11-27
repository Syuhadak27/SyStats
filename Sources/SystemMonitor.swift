import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// CPU and RAM usage from Mach host statistics (no external processes).
enum SystemMonitor {
    private static let lock = NSLock()
    private static var previousTicks: (user: Double, system: Double, idle: Double, nice: Double)?

    static func cpuUsagePercent() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let total = user + system + idle + nice

        lock.lock()
        defer { lock.unlock() }
        guard let previous = previousTicks else {
            previousTicks = (user, system, idle, nice)
            return nil // first sample has no delta yet
        }
        previousTicks = (user, system, idle, nice)

        let deltaTotal = total - (previous.user + previous.system + previous.idle + previous.nice)
        guard deltaTotal > 0 else { return nil }
        let deltaIdle = idle - previous.idle
        let usage = (1.0 - deltaIdle / deltaTotal) * 100.0
        return Swift.min(Swift.max(usage, 0), 100)
    }

    static func ramUsagePercent() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        let pageSize = Double(getpagesize())
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wired_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        return Swift.min(Swift.max(used / total * 100.0, 0), 100)
    }
}
