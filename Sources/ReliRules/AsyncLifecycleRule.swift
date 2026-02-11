import Foundation
import ReliCore

/// Detects asynchronous work that may outlive the lifecycle of a view or
/// view controller. The rule looks for patterns such as `Task {}` blocks,
/// scheduled timers and delayed dispatches without corresponding cancellation
/// or deinitialisation handling. This heuristic implementation may emit
/// false positives; use your judgement when interpreting findings.
public struct AsyncLifecycleRule: Rule {
    public let id = "async-lifecycle"
    public let description = "Detects async work that may outlive view/controller lifecycle"
    
    private let asyncThreshold: Int
    private let cancelHintThreshold: Int

    /// - Parameters:
    ///   - asyncThreshold: Total async-related patterns required to trigger a finding.
    ///   - cancelHintThreshold: Minimum cancellation/deinit hints expected before suppressing a finding.
    ///
    /// Defaults are tuned to surface a small number of actionable lifecycle issues
    /// in typical UIKit view controllers.
    public init(asyncThreshold: Int = 3, cancelHintThreshold: Int = 1) {
        self.asyncThreshold = asyncThreshold
        self.cancelHintThreshold = cancelHintThreshold
    }

    public func check(_ context: LintContext) throws -> [Finding] {
        var findings: [Finding] = []
        let taskPattern = try! NSRegularExpression(pattern: "\\bTask\\s*\\{", options: [])
        let timerPattern = try! NSRegularExpression(pattern: "\\bTimer\\.scheduledTimer", options: [])
        let dispatchAfterPattern = try! NSRegularExpression(pattern: "\\bDispatchQueue\\..*asyncAfter", options: [])
        let cancelPattern = try! NSRegularExpression(pattern: "\\bcancel\\(", options: [])
        let deinitPattern = try! NSRegularExpression(pattern: "\\bdeinit\\b", options: [])
        for (path, text) in context.fileContents {
            guard path.hasSuffix(".swift") else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let taskCount = taskPattern.numberOfMatches(in: text, options: [], range: range)
            let timerCount = timerPattern.numberOfMatches(in: text, options: [], range: range)
            let dispatchAfterCount = dispatchAfterPattern.numberOfMatches(in: text, options: [], range: range)
            let cancelCount = cancelPattern.numberOfMatches(in: text, options: [], range: range)
            let deinitCount = deinitPattern.numberOfMatches(in: text, options: [], range: range)
            let typeNames = extractRelevantTypeNames(from: text)
            let asyncTotal = taskCount + timerCount + dispatchAfterCount
            let cancelHints = cancelCount + deinitCount
            if asyncTotal >= asyncThreshold && cancelHints < cancelHintThreshold {
                let issueLine = firstIssueLine(
                    in: text,
                    patterns: [taskPattern, timerPattern, dispatchAfterPattern]
                )
                var evidence: [String: String] = [
                    "taskCount": "\(taskCount)",
                    "timerCount": "\(timerCount)",
                    "dispatchAfterCount": "\(dispatchAfterCount)",
                    "asyncTotal": "\(asyncTotal)",
                    "cancelOrDeinitHints": "\(cancelHints)",
                    "asyncThreshold": "\(asyncThreshold)",
                    "cancelHintThreshold": "\(cancelHintThreshold)"
                ]
                if !typeNames.isEmpty {
                    evidence["typeNames"] = typeNames.joined(separator: ", ")
                }
                let finding = Finding(
                    ruleID: id,
                    title: "Async work may outlive lifecycle",
                    message: "Found many async/timer patterns (\(asyncTotal)) without cancellation or deinit handling.",
                    severity: asyncTotal >= max(asyncThreshold * 2, 6) ? .high : .medium,
                    filePath: path,
                    line: issueLine,
                    column: nil,
                    typeName: typeNames.first,
                    evidence: evidence,
                    snippet: SnippetBuilder.around(text: text, line: issueLine)
                )
                findings.append(finding)
            }
        }
        return findings
    }

    private func extractRelevantTypeNames(from text: String) -> [String] {
        let declarationPattern = try! NSRegularExpression(
            pattern: "\\b(?:final\\s+)?(?:public\\s+|internal\\s+|private\\s+|fileprivate\\s+|open\\s+)?(?:class|struct|actor)\\s+([A-Z][A-Za-z0-9_]*)",
            options: []
        )
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = declarationPattern.matches(in: text, options: [], range: range)

        var allNames: [String] = []
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            if !allNames.contains(name) {
                allNames.append(name)
            }
        }

        let targetSuffixes = ["ViewController", "VC", "ViewModel", "VM"]
        let focused = allNames.filter { name in
            targetSuffixes.contains { name.hasSuffix($0) }
        }
        return focused.isEmpty ? allNames : focused
    }

    private func firstIssueLine(in text: String, patterns: [NSRegularExpression]) -> Int? {
        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var smallestLocation: Int?

        for pattern in patterns {
            guard let match = pattern.firstMatch(in: text, options: [], range: searchRange) else { continue }
            if let current = smallestLocation {
                smallestLocation = min(current, match.range.location)
            } else {
                smallestLocation = match.range.location
            }
        }

        guard let location = smallestLocation else { return nil }
        return SnippetBuilder.lineNumber(in: text, utf16Offset: location)
    }
}
