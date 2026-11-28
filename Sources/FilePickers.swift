import SwiftUI
#if os(macOS)
import AppKit

enum FilePickers {
    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select the EFI folder (e.g. /Volumes/EFI/EFI)"
        panel.prompt = "Choose EFI"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// `message` menjelaskan file apa yang diminta (dulu selalu "Select a PNG
    /// asset", termasuk saat memilih executable helper).
    static func chooseFile(message: String = "Select a file") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
#endif
