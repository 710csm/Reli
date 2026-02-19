import Foundation
import ReliCore
@testable import reli

enum TestUtils {
    static func makeFinding(title: String, severity: Severity) -> Finding {
        Finding(
            ruleID: "test-rule",
            title: title,
            message: "message",
            severity: severity,
            filePath: "Sources/Test.swift",
            line: 1
        )
    }

    static func parseReliCommand(_ arguments: [String]) throws -> ReliCommand {
        let parsed = try ReliCommand.parseAsRoot(arguments)
        guard let command = parsed as? ReliCommand else {
            throw NSError(
                domain: "ReliTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse ReliCommand."]
            )
        }
        return command
    }
}
