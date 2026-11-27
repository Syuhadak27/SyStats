import Foundation
import AppKit
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Persisted preferences. Values are intentionally simple so they survive
/// restarts and are easy to inspect in UserDefaults.
final class PreferencesStore: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var efiFolderPath: String {
        didSet { defaults.set(efiFolderPath, forKey: "efiFolderPath") }
    }
    @Published var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: "pollInterval") }
    }
    @Published var menuBarModeRaw: String {
        didSet { defaults.set(menuBarModeRaw, forKey: "menuBarMode") }
    }
    @Published var compactMenuBar: Bool {
        didSet { defaults.set(compactMenuBar, forKey: "compactMenuBar") }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: "hideDockIcon")
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(self.hideDockIcon ? .accessory : .regular)
                if !self.hideDockIcon { NSApp.activate(ignoringOtherApps: true) }
            }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            setLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var menuBarAssetPath: String {
        didSet { defaults.set(menuBarAssetPath, forKey: "menuBarAssetPath") }
    }
    @Published var appIconAssetPath: String {
        didSet { defaults.set(appIconAssetPath, forKey: "appIconAssetPath") }
    }
    @Published var helperCommandPath: String {
        didSet { defaults.set(helperCommandPath, forKey: "helperCommandPath") }
    }
    @Published var selectedAdapterID: String {
        didSet { defaults.set(selectedAdapterID, forKey: "selectedAdapterID") }
    }
    @Published var thresholdStart: Int {
        didSet { defaults.set(thresholdStart, forKey: "thresholdStart") }
    }
    @Published var thresholdStop: Int {
        didSet { defaults.set(thresholdStop, forKey: "thresholdStop") }
    }
    @Published var thresholdEnabled: Bool {
        didSet { defaults.set(thresholdEnabled, forKey: "thresholdEnabled") }
    }
    /// true hanya setelah pengguna menekan Apply (atau menyalakan toggle) dan
    /// berhasil. Sebelum itu timer reapply TIDAK boleh menulis ke hardware.
    @Published var thresholdAutoReapply: Bool {
        didSet { defaults.set(thresholdAutoReapply, forKey: "thresholdAutoReapply") }
    }
    @Published var thresholdReapplyInterval: Double {
        didSet { defaults.set(thresholdReapplyInterval, forKey: "thresholdReapplyInterval") }
    }
    @Published var batteryIndex: Int {
        didSet { defaults.set(batteryIndex, forKey: "batteryIndex") }
    }
    @Published var ecDirectEnabled: Bool {
        didSet { defaults.set(ecDirectEnabled, forKey: "ecDirectEnabled") }
    }
    @Published var ecStartOffset: Int {
        didSet { defaults.set(ecStartOffset, forKey: "ecStartOffset") }
    }
    @Published var ecStopOffset: Int {
        didSet { defaults.set(ecStopOffset, forKey: "ecStopOffset") }
    }
    @Published var ecInhibitOffset: Int {
        didSet { defaults.set(ecInhibitOffset, forKey: "ecInhibitOffset") }
    }

    var menuBarMode: MenuBarMode {
        get { MenuBarMode(rawValue: menuBarModeRaw) ?? .automatic }
        set { menuBarModeRaw = newValue.rawValue }
    }

    init() {
        efiFolderPath = defaults.string(forKey: "efiFolderPath") ?? ""
        pollInterval = defaults.object(forKey: "pollInterval") as? Double ?? 2.0
        menuBarModeRaw = defaults.string(forKey: "menuBarMode") ?? MenuBarMode.automatic.rawValue
        compactMenuBar = defaults.object(forKey: "compactMenuBar") as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        hideDockIcon = defaults.object(forKey: "hideDockIcon") as? Bool ?? false
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        menuBarAssetPath = defaults.string(forKey: "menuBarAssetPath") ?? ""
        appIconAssetPath = defaults.string(forKey: "appIconAssetPath") ?? ""
        helperCommandPath = defaults.string(forKey: "helperCommandPath") ?? ""
        selectedAdapterID = defaults.string(forKey: "selectedAdapterID") ?? "thinkVPC"
        thresholdStart = defaults.object(forKey: "thresholdStart") as? Int ?? 75
        thresholdStop = defaults.object(forKey: "thresholdStop") as? Int ?? 85
        thresholdEnabled = defaults.object(forKey: "thresholdEnabled") as? Bool ?? true
        thresholdAutoReapply = defaults.object(forKey: "thresholdAutoReapply") as? Bool ?? false
        thresholdReapplyInterval = defaults.object(forKey: "thresholdReapplyInterval") as? Double ?? 3.0
        batteryIndex = defaults.object(forKey: "batteryIndex") as? Int ?? 1
        ecDirectEnabled = defaults.object(forKey: "ecDirectEnabled") as? Bool ?? false
        ecStartOffset = defaults.object(forKey: "ecStartOffset") as? Int ?? 0
        ecStopOffset = defaults.object(forKey: "ecStopOffset") as? Int ?? 0
        ecInhibitOffset = defaults.object(forKey: "ecInhibitOffset") as? Int ?? 0
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login update failed: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
