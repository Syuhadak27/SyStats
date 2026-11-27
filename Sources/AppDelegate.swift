import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppEnvironment.shared
        NSApp.setActivationPolicy(state.preferences.hideDockIcon ? .accessory : .regular)
        state.scanEFI()
        let controller = MenuBarController(appState: state)
        controller.setup()
        menuBarController = controller

        // Mode "menu bar only" tidak membuka jendela saat start.
        if !state.preferences.hideDockIcon {
            MainWindowController.shared.show()
        }
    }

    /// The app stays alive (menu bar) after the full GUI window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Klik ikon Dock saat jendela tertutup/diminimalkan → tampilkan lagi.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.show() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
