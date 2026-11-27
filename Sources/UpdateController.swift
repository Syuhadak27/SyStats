import Foundation
import Sparkle

/// Jembatan ke Sparkle 2 untuk cek update dari GitHub Releases.
///
/// Feed: `SUFeedURL` di Info.plist → appcast.xml di branch main.
/// Tanda tangan: Ed25519 (`SUPublicEDKey` di Info.plist).
/// Automatic checks diaktifkan via `SUEnableAutomaticChecks` + interval 24 jam.
final class UpdateController {
    static let shared = UpdateController()

    /// Controller standar Sparkle: membuat SPUUpdater + SPUStandardUserDriver,
    /// langsung start, dan menyediakan UI native untuk prompt update.
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Dipanggil dari "Check for Updates…" di popover.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Versi saat ini dari bundle (untuk tooltip UI).
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
