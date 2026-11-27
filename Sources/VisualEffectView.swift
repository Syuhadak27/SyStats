import SwiftUI

#if os(macOS)
import AppKit

/// NSVisualEffectView bridge for modern "glass" cards.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // `.inactive` jauh lebih ringan daripada `.active`: tetap memberi
        // efek blur statis tanpa terus-menerus mengomposit ulang saat
        // window/telemetri berubah tiap beberapa detik.
        view.state = .inactive
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif
