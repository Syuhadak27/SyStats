import Foundation

/// Locates an EFI folder. Detection is read-only and deliberately conservative.
enum EFIDetector {
    static let defaultRelativePath = "EFI/OC/ACPI"

    static func detectRoot(savedPath: String?) -> URL? {
        var candidates: [URL] = []
        if let savedPath, !savedPath.isEmpty {
            candidates.append(URL(fileURLWithPath: (savedPath as NSString).expandingTildeInPath))
        }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/Volumes/EFI/EFI"),
            URL(fileURLWithPath: "/Volumes/EFI"),
            URL(fileURLWithPath: "/Volumes/ESP/EFI"),
            URL(fileURLWithPath: "/Volumes/ESP"),
            URL(fileURLWithPath: "/Volumes/NO NAME/EFI"),
            URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/EFI")),
            URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("EFI")),
            URL(fileURLWithPath: "EFI"), // development workspace / relative path
        ])
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               FileManager.default.isReadableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    static func acpiDirectories(for root: URL) -> [URL] {
        let relative = ["OC/ACPI", "APPLE/ACPI", "ACPI"]
        return relative.compactMap { component in
            let url = root.appendingPathComponent(component, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return url
        }
    }

    static func configURL(for root: URL) -> URL? {
        let candidates = [
            root.appendingPathComponent("OC/config.plist"),
            root.appendingPathComponent("APPLE/config.plist"),
            root.appendingPathComponent("config.plist"),
        ]
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }
}
