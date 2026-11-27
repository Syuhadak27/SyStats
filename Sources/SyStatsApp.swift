import SwiftUI
import AppKit

/// Entry point. Jendela utama dibuat oleh `MainWindowController` (AppKit) dan
/// status item oleh `MenuBarController`; scene SwiftUI di bawah hanya
/// placeholder karena `App` wajib punya minimal satu scene.
@main
struct SyStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                // Hilangkan menu "Settings…" yang akan membuka jendela kosong.
                CommandGroup(replacing: .appSettings) { }
            }
    }
}
