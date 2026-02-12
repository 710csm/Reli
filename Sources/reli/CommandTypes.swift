import Foundation
import ReliCore
import ArgumentParser

/// Controls CI failure behavior based on finding severity.
enum FailOn: String, ExpressibleByArgument {
    case off
    case low
    case medium
    case high

    /// Maps CLI option values to lint severity thresholds.
    var threshold: Severity? {
        switch self {
        case .off:
            return nil
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }
}

/// Controls whether CI annotations are emitted.
enum AnnotationsMode: String, ExpressibleByArgument {
    case off
    case github
}

/// Controls how file paths are rendered in reports.
enum PathStyle: String, ExpressibleByArgument {
    case relative
    case absolute
}
