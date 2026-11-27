import AppKit
import SwiftUI

/// Jendela utama dikelola langsung lewat AppKit (bukan `WindowGroup`).
///
/// Alasan: aplikasi ini hidup di menu bar. Dengan `WindowGroup`, setelah jendela
/// ditutup tombol "Open Full GUI" di popover tidak punya cara andal untuk
/// membuatnya lagi, sehingga dashboard "hilang" sampai app dijalankan ulang.
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    /// Tampilkan jendela; dibuat ulang bila belum ada. Aman dipanggil berulang.
    func show() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let state = AppEnvironment.shared
        let rootView = ContentView()
            .environmentObject(state)
            .environmentObject(state.telemetry)
            .environmentObject(state.thresholds)
            .environmentObject(state.preferences)
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "SyStats"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false // jendela dipakai ulang setelah ditutup
        window.setContentSize(NSSize(width: 900, height: 680))
        window.contentMinSize = NSSize(width: 780, height: 560)
        window.center()
        window.setFrameAutosaveName("SyStatsMainWindow") // pulihkan posisi/ukuran terakhir
        window.delegate = self
        return window
    }
}
