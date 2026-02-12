import Foundation
import ReliCore
import ArgumentParser

enum FailOn: String, ExpressibleByArgument {
    case off
    case low
    case medium
    case high

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

enum AnnotationsMode: String, ExpressibleByArgument {
    case off
    case github
}

enum PathStyle: String, ExpressibleByArgument {
    case relative
    case absolute
}
