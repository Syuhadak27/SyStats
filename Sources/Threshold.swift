import Foundation

/// User-intent configuration. It is persisted locally, but the GUI always
/// distinguishes "desired" from "confirmed by adapter read-back".
struct ThresholdConfiguration: Equatable, Sendable {
    var startPercent: Int = 80
    var stopPercent: Int = 100
    var adapterID: String = "thinkVPC"
    var confirmedByAdapter = false
    var appliedAt: Date?

    static let minimumGap = 5
}

enum ThresholdValidation {
    static func message(start: Int, stop: Int) -> String? {
        guard (0...100).contains(start), (0...100).contains(stop) else {
            return "Start and Stop must be between 0% and 100%."
        }
        guard stop > start else {
            return "Stop threshold must be higher than Start threshold."
        }
        guard stop - start >= ThresholdConfiguration.minimumGap else {
            return "Keep at least a \(ThresholdConfiguration.minimumGap)% gap between Start and Stop."
        }
        return nil
    }
}

struct ThresholdOperationResult: Sendable {
    var success: Bool
    /// `true` hanya bila adapter melakukan read-back yang cocok (mis. RE1B).
    var verified: Bool = false
    var message: String
    var details: [String] = []
    var timestamp: Date = Date()

    var statusLabel: String {
        if !success { return "Failed" }
        return verified ? "Applied & verified" : "Applied (unverified)"
    }
}
