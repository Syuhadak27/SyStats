import Foundation

/// Single shared state so the AppKit status item and SwiftUI windows always
/// observe the same telemetry, inspection and threshold objects.
enum AppEnvironment {
    static let shared = AppState()
}
