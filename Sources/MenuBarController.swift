import AppKit
import SwiftUI
import Combine

/// NSStatusItem bridge: icon + live telemetry title + transient control popover.
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func setup() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "SyStats — click for quick controls"
        button.imagePosition = .imageLeft
        // Angka lebar tetap supaya teks menu bar tidak "bergoyang" tiap update.
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)

        let rootView = MenuBarPopoverView().environmentObject(appState)
        let hosting = NSHostingController(rootView: rootView)
        hosting.preferredContentSize = NSSize(width: 330, height: 560)
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        updateIcon()
        updateTitle(appState.telemetry.snapshot)

        appState.telemetry.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateTitle($0) }
            .store(in: &cancellables)

        appState.preferences.$menuBarModeRaw
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle(self?.appState.telemetry.snapshot ?? TelemetrySnapshot()) }
            .store(in: &cancellables)

        appState.preferences.$compactMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle(self?.appState.telemetry.snapshot ?? TelemetrySnapshot()) }
            .store(in: &cancellables)

        appState.preferences.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.preferences.$menuBarAssetPath
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        guard appState.preferences.showMenuBarIcon else {
            button.image = nil
            return
        }
        let customPath = appState.preferences.menuBarAssetPath
        var image: NSImage?
        if !customPath.isEmpty {
            let expanded = (customPath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                image = NSImage(contentsOfFile: expanded)
            }
        }
        image = image ?? NSImage(named: "MenuBarIcon")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true // crisp monochrome rendering on any wallpaper
        button.image = image
    }

    private func updateTitle(_ snapshot: TelemetrySnapshot) {
        guard let button = statusItem.button else { return }
        let text = snapshot.menuBarText(
            mode: appState.preferences.menuBarMode,
            compact: appState.preferences.compactMenuBar
        )
        button.title = text
        button.setAccessibilityLabel(snapshot.menuBarAccessibilityLabel)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // App accessory/regular perlu diaktifkan agar popover menerima klik.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
