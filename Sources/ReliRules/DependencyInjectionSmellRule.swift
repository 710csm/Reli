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
    private let singletonAllowlist: Set<String>
    private let excludedInstantiationTypes: Set<String>

    /// - Parameters:
    ///   - sharedThreshold: Triggers when `.shared` singleton usage count exceeds this value.
    ///   - instantiationThreshold: Triggers when direct `Type(...)` instantiation count exceeds this value.
    ///
    /// Defaults are set to be moderately sensitive so that real-world codebases surface
    /// a small number of actionable findings.
    public init(
        sharedThreshold: Int = 5,
        instantiationThreshold: Int = 20,
        singletonAllowlist: Set<String> = [],
        excludedInstantiationTypes: Set<String>? = nil
    ) {
        self.sharedThreshold = sharedThreshold
        self.instantiationThreshold = instantiationThreshold
        self.singletonAllowlist = singletonAllowlist
        self.excludedInstantiationTypes = excludedInstantiationTypes ?? Self.defaultExcludedInstantiationTypes
    }

    public func check(_ context: LintContext) throws -> [Finding] {
        var findings: [Finding] = []
        let singletonPattern = try! NSRegularExpression(pattern: "\\b([A-Z][A-Za-z0-9_]*)\\s*\\.\\s*(shared|default)\\b", options: [])
        let instantiationPattern = try! NSRegularExpression(pattern: "\\b([A-Z][A-Za-z0-9_]*)\\s*(?:<[^>]+>)?\\s*\\(", options: [])
        for (path, text) in context.fileContents {
            guard path.hasSuffix(".swift") else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let singletonMatches = singletonPattern.matches(in: text, options: [], range: range)
            let instantiationMatches = instantiationPattern.matches(in: text, options: [], range: range)
            let singletonDetails = singletonMatches.compactMap { match -> (location: Int, token: String)? in
                guard
                    let typeRange = Range(match.range(at: 1), in: text),
                    let accessorRange = Range(match.range(at: 2), in: text)
                else { return nil }
                let token = "\(text[typeRange]).\(text[accessorRange])"
                return (location: match.range.location, token: token)
            }
            let filteredSingleton = singletonDetails.filter { !singletonAllowlist.contains($0.token) }
            let singletonCount = filteredSingleton.count

            let instantiationDetails = instantiationMatches.compactMap { match -> (location: Int, type: String)? in
                guard let typeRange = Range(match.range(at: 1), in: text) else { return nil }
                return (location: match.range.location, type: String(text[typeRange]))
            }
            let filteredInstantiation = instantiationDetails.filter { !excludedInstantiationTypes.contains($0.type) }
            let instantiationCount = filteredInstantiation.count
            let typeNames = extractRelevantTypeNames(from: text)
            if singletonCount >= sharedThreshold || instantiationCount >= instantiationThreshold {
                let severity: Severity = (singletonCount >= max(sharedThreshold * 2, 12) || instantiationCount >= max(instantiationThreshold * 2, 40)) ? .high : .medium
                let issueLine = firstIssueLine(
                    in: text,
                    singletonLocations: filteredSingleton.map(\.location),
                    instantiationLocations: filteredInstantiation.map(\.location)
                )
                var evidence: [String: String] = [
                    "singletonUsageCount": "\(singletonCount)",
                    "rawSingletonUsageCount": "\(singletonDetails.count)",
                    "directInstantiationCount": "\(instantiationCount)",
                    "rawDirectInstantiationCount": "\(instantiationDetails.count)",
                    "sharedThreshold": "\(sharedThreshold)",
                    "instantiationThreshold": "\(instantiationThreshold)",
                    "singletonAllowlist": singletonAllowlist.sorted().joined(separator: ", "),
                    "excludedInstantiationTypesCount": "\(excludedInstantiationTypes.count)"
                ]
                if !excludedInstantiationTypes.isEmpty {
                    evidence["excludedInstantiationTypesSample"] = excludedInstantiationTypes.sorted().prefix(12).joined(separator: ", ")
                }
                if !typeNames.isEmpty {
                    evidence["typeNames"] = typeNames.joined(separator: ", ")
                }
                let finding = Finding(
                    ruleID: id,
                    title: "Tight coupling / DI smell",
                    message: "This file contains frequent singleton access (`.shared`/`.default`) (\(singletonCount)) or direct instantiations (\(instantiationCount)) after filtering framework/value-object construction noise. Consider using protocols and dependency injection.",
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

    private func firstIssueLine(
        in text: String,
        singletonLocations: [Int],
        instantiationLocations: [Int]
    ) -> Int? {
        let location = (singletonLocations + instantiationLocations).min()
        guard let location else { return nil }
        return SnippetBuilder.lineNumber(in: text, utf16Offset: location)
    }

    private static let defaultExcludedInstantiationTypes: Set<String> = [
        "CGPoint", "CGSize", "CGRect", "CGAffineTransform", "CGVector",
        "UIEdgeInsets", "NSDirectionalEdgeInsets", "UIColor", "UIImage", "UIFont",
        "URL", "URLRequest", "Date", "DateComponents", "IndexPath", "NSRange",
        "Int", "Double", "Float", "Bool", "String", "Character", "UUID"
    ]
}
