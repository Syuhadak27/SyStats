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
    }

    /// The app stays alive (menu bar) after the full GUI window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
