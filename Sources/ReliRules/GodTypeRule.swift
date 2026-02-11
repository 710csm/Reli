import Foundation
import ReliCore

/// Flags types that are likely doing too much. This implementation uses a
/// simple heuristic based on the number of lines and functions in a file. In
/// the future this could leverage SwiftSyntax to analyse declarations and
/// measure true complexity. The heuristic thresholds are deliberately set
/// conservatively; adjust them to your team's conventions as needed.
public struct GodTypeRule: Rule {
    public let id = "god-type"
    public let description = "Detects overly large types (e.g. view controllers or view models)"
    
    private let lineThreshold: Int
    private let functionThreshold: Int

    /// - Parameters:
    ///   - lineThreshold: Triggers when a file exceeds this many lines.
    ///   - functionThreshold: Triggers when a file exceeds this many `func` declarations.
    ///
    /// Defaults are intentionally set to be a bit more sensitive so that most real-world
    /// codebases will surface a small number of actionable findings.
    public init(lineThreshold: Int = 300, functionThreshold: Int = 20) {
        self.lineThreshold = lineThreshold
        self.functionThreshold = functionThreshold
    }

    public func check(_ context: LintContext) throws -> [Finding] {
        var findings: [Finding] = []
        for (path, text) in context.fileContents {
            guard path.hasSuffix(".swift") else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let lineCount = lines.count
            // Count the number of lines that define a function by scanning for "func "
            let funcCount = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("func ") }.count
            // Trigger a finding if either threshold is exceeded. Lower thresholds produce more
            // suggestions; you may wish to tune these depending on your codebase size.
            if lineCount >= lineThreshold || funcCount >= functionThreshold {
                let severity: Severity = (lineCount >= max(lineThreshold * 2, 600) || funcCount >= max(functionThreshold * 2, 40)) ? .high : .medium
                let issueLine = issueLineNumber(lines: lines, lineCount: lineCount)
                let snippet = SnippetBuilder.around(text: text, line: issueLine)
                let finding = Finding(
                    ruleID: id,
                    title: "Massive type suspected",
                    message: "This file appears to be very large (\(lineCount) lines, \(funcCount) functions). Consider splitting responsibilities into smaller types.",
                    severity: severity,
                    filePath: path,
                    line: issueLine,
                    column: nil,
                    evidence: [
                        "lineCount": "\(lineCount)",
                        "funcCount": "\(funcCount)",
                        "lineThreshold": "\(lineThreshold)",
                        "functionThreshold": "\(functionThreshold)"
                    ],
                    snippet: snippet
                )
                findings.append(finding)
            }
        }
        return findings
    }

    private func issueLineNumber(lines: [Substring], lineCount: Int) -> Int {
        if lineCount >= lineThreshold {
            return min(lineThreshold, lineCount)
        }

        var functionSeen = 0
        for (idx, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("func ") {
                functionSeen += 1
                if functionSeen == functionThreshold {
                    return idx + 1
                }
            }
        }
        return min(max(1, lineCount / 2), max(1, lineCount))
    }
}
