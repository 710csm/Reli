import Foundation
import ReliCore

/// Detects patterns that suggest poor dependency injection practices. The
/// implementation counts occurrences of `.shared` singletons and direct
/// instantiations of types in the file. When counts exceed heuristic
/// thresholds a finding is emitted. In a future version this rule could
/// inspect initializer signatures and call sites with SwiftSyntax for more
/// precision.
public struct DependencyInjectionSmellRule: Rule {
    public let id = "di-smell"
    public let description = "Detects direct instantiation and singleton usage that reduce testability"
    
    private let sharedThreshold: Int
    private let instantiationThreshold: Int

    /// - Parameters:
    ///   - sharedThreshold: Triggers when `.shared` singleton usage count exceeds this value.
    ///   - instantiationThreshold: Triggers when direct `Type(...)` instantiation count exceeds this value.
    ///
    /// Defaults are set to be moderately sensitive so that real-world codebases surface
    /// a small number of actionable findings.
    public init(sharedThreshold: Int = 5, instantiationThreshold: Int = 20) {
        self.sharedThreshold = sharedThreshold
        self.instantiationThreshold = instantiationThreshold
    }

    public func check(_ context: LintContext) throws -> [Finding] {
        var findings: [Finding] = []
        let singletonPattern = try! NSRegularExpression(pattern: "\\.shared\\b", options: [])
        let instantiationPattern = try! NSRegularExpression(pattern: "\\b[A-Z][A-Za-z0-9_]*\\s*\\(", options: [])
        for (path, text) in context.fileContents {
            guard path.hasSuffix(".swift") else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let singletonCount = singletonPattern.numberOfMatches(in: text, options: [], range: range)
            let instantiationCount = instantiationPattern.numberOfMatches(in: text, options: [], range: range)
            let typeNames = extractRelevantTypeNames(from: text)
            if singletonCount >= sharedThreshold || instantiationCount >= instantiationThreshold {
                let severity: Severity = (singletonCount >= max(sharedThreshold * 2, 12) || instantiationCount >= max(instantiationThreshold * 2, 40)) ? .high : .medium
                let issueLine = firstIssueLine(
                    in: text,
                    patterns: [singletonPattern, instantiationPattern]
                )
                var evidence: [String: String] = [
                    "singletonUsageCount": "\(singletonCount)",
                    "directInstantiationCount": "\(instantiationCount)",
                    "sharedThreshold": "\(sharedThreshold)",
                    "instantiationThreshold": "\(instantiationThreshold)"
                ]
                if !typeNames.isEmpty {
                    evidence["typeNames"] = typeNames.joined(separator: ", ")
                }
                let finding = Finding(
                    ruleID: id,
                    title: "Tight coupling / DI smell",
                    message: "This file contains frequent `.shared` singleton usage (\(singletonCount)) or direct instantiations (\(instantiationCount)). Consider using protocols and dependency injection.",
                    severity: severity,
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
