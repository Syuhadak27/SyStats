import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Uses the bundled AppIcon (from icon.png) unless a custom file is selected.
enum AppBranding {
    #if os(macOS)
    /// Cache gambar per path. `icon(preferences:)` dipanggil dari `body` view,
    /// jadi dulu `NSImage(contentsOfFile:)` membaca disk di setiap render ulang.
    /// Hanya dipakai dari main thread (body SwiftUI).
    private static var cache: [String: NSImage] = [:]
    #endif

    static func icon(preferences: PreferencesStore? = nil) -> Image? {
        #if os(macOS)
        if let path = preferences?.appIconAssetPath, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if let cached = cache[expanded] { return Image(nsImage: cached) }
            if let image = NSImage(contentsOfFile: expanded) {
                cache[expanded] = image
                return Image(nsImage: image)
            }
        }
        if let cached = cache["#bundled"] { return Image(nsImage: cached) }
        if let image = NSImage(named: "AppIcon") ?? NSApp?.applicationIconImage {
            cache["#bundled"] = image
            return Image(nsImage: image)
        }
        return Image(systemName: "bolt.batteryblock.fill")
        #else
        return Image(systemName: "bolt.batteryblock.fill")
        #endif
    }
}
