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
        } else if let window, window.contentViewController == nil {
            // Jendela pernah ditutup: isi SwiftUI dibuang saat itu (lihat
            // windowWillClose). Pasang lagi tanpa mengubah ukuran/posisi jendela.
            let frame = window.frame
            window.contentViewController = makeHostingController()
            window.setFrame(frame, display: false)
        }
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeHostingController() -> NSViewController {
        let state = AppEnvironment.shared
        let rootView = ContentView()
            .environmentObject(state)
            .environmentObject(state.telemetry)
            .environmentObject(state.thresholds)
            .environmentObject(state.preferences)
        let controller = NSHostingController(rootView: rootView)
        // Default (macOS 13+) membuat hosting controller menghitung ulang
        // min/ideal/max size seluruh pohon SwiftUI pada setiap perubahan layout,
        // yang membuat resize jendela dan scroll terasa patah-patah. Ukuran
        // jendela sudah diatur sendiri (contentMinSize) jadi tidak perlu.
        controller.sizingOptions = []
        return controller
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: makeHostingController())
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

    /// Setelah jendela ditutup, app tetap hidup di menu bar. Buang isi SwiftUI
    /// supaya dashboard tidak terus dievaluasi tiap poll saat tidak terlihat.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, !window.isVisible else { return }
            window.contentViewController = nil
            // Pastikan view hosting lama benar-benar lepas dari jendela.
            window.contentView = NSView(frame: .zero)
        }
    }
}
