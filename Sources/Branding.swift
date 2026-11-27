import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Uses the bundled AppIcon (from icon.png) unless a custom file is selected.
enum AppBranding {
    static func icon(preferences: PreferencesStore? = nil) -> Image? {
        #if os(macOS)
        if let path = preferences?.appIconAssetPath, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if let image = NSImage(contentsOfFile: expanded) {
                return Image(nsImage: image)
            }
        }
        if let image = NSImage(named: "AppIcon") {
            return Image(nsImage: image)
        }
        return Image(systemName: "bolt.batteryblock.fill")
        #else
        return Image(systemName: "bolt.batteryblock.fill")
        #endif
    }
}
