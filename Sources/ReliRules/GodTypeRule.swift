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
            let analysis = analyze(text: text)
            let lineCount = analysis.lineCount
            let funcCount = analysis.functions.count
            // Trigger a finding if either threshold is exceeded. Lower thresholds produce more
            // suggestions; you may wish to tune these depending on your codebase size.
            if lineCount >= lineThreshold || funcCount >= functionThreshold {
                let severity: Severity = (lineCount >= max(lineThreshold * 2, 600) || funcCount >= max(functionThreshold * 2, 40)) ? .high : .medium
                let issueLine = issueLineNumber(lineCount: lineCount, functions: analysis.functions)
                let snippet = SnippetBuilder.around(text: text, line: issueLine)
                let confidence = countingConfidence(analysis: analysis)
                let topFunctions = analysis.functions
                    .sorted { lhs, rhs in
                        if lhs.lineSpan == rhs.lineSpan { return lhs.startLine < rhs.startLine }
                        return lhs.lineSpan > rhs.lineSpan
                    }
                    .prefix(10)
                    .map { "\($0.name)(\($0.lineSpan)L)" }
                    .joined(separator: ", ")
                let avgFunctionLines: String = {
                    guard !analysis.functions.isEmpty else { return "0.0" }
                    let total = analysis.functions.reduce(0) { $0 + $1.lineSpan }
                    return String(format: "%.1f", Double(total) / Double(analysis.functions.count))
                }()
                let maxFunctionLines = analysis.functions.map(\.lineSpan).max() ?? 0
                let focusedTypeNames = analysis.typeNames.filter {
                    $0.hasSuffix("ViewController") || $0.hasSuffix("VC") || $0.hasSuffix("ViewModel") || $0.hasSuffix("VM")
                }
                let chosenTypeName = (focusedTypeNames.isEmpty ? analysis.typeNames : focusedTypeNames).first
                let prefixGroups = groupedFunctionPrefixes(from: analysis.functions)
                    .prefix(8)
                    .map { "\($0.prefix): \($0.count)" }
                    .joined(separator: ", ")
                let markSections = analysis.markSections.prefix(8).joined(separator: ", ")
                var message = "This file appears large (\(lineCount) lines, \(funcCount) functions by regex counting). Consider splitting responsibilities into smaller types."
                if let chosenTypeName {
                    message = "Type `\(chosenTypeName)` appears large (\(lineCount) lines, \(funcCount) functions by regex counting). Consider splitting responsibilities by feature boundaries."
                }
                message += " Counting method: regex (v0.1), confidence: \(confidence)."
                let finding = Finding(
                    ruleID: id,
                    title: "Massive type suspected",
                    message: message,
                    severity: severity,
                    filePath: path,
                    line: issueLine,
                    column: nil,
                    typeName: chosenTypeName,
                    evidence: [
                        "lineCount": "\(lineCount)",
                        "funcCount": "\(funcCount)",
                        "lineThreshold": "\(lineThreshold)",
                        "functionThreshold": "\(functionThreshold)",
                        "typeName": chosenTypeName ?? "",
                        "topFunctionNames": topFunctions,
                        "avgFunctionLines": avgFunctionLines,
                        "maxFunctionLines": "\(maxFunctionLines)",
                        "extensionCount": "\(analysis.extensionCount)",
                        "uiActionCount": "\(analysis.uiActionCount)",
                        "functionPrefixGroups": prefixGroups.isEmpty ? "none" : prefixGroups,
                        "markSections": markSections.isEmpty ? "none" : markSections,
                        "countingMethod": "regex (v0.1)",
                        "countingConfidence": confidence
                    ],
                    snippet: snippet
                )
                findings.append(finding)
            }
        }
        return findings
    }

    private func issueLineNumber(lineCount: Int, functions: [FunctionMetric]) -> Int {
        if lineCount >= lineThreshold {
            return min(lineThreshold, lineCount)
        }

        if functions.count >= functionThreshold {
            return functions[functionThreshold - 1].startLine
        }
        return min(max(1, lineCount / 2), max(1, lineCount))
    }

    private func analyze(text: String) -> FileAnalysis {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lineCount = lines.count
        let functionPattern = try! NSRegularExpression(
            pattern: "(?m)^\\s*(?:public|private|internal|fileprivate|open)?\\s*(?:static|class)?\\s*func\\s+([A-Za-z_][A-Za-z0-9_]*)",
            options: []
        )
        let typePattern = try! NSRegularExpression(
            pattern: "(?m)^\\s*(?:final\\s+)?(?:public|private|internal|fileprivate|open)?\\s*(?:class|struct|actor)\\s+([A-Z][A-Za-z0-9_]*)",
            options: []
        )
        let extensionPattern = try! NSRegularExpression(
            pattern: "(?m)^\\s*extension\\s+[A-Z][A-Za-z0-9_]*",
            options: []
        )
        let uiActionPattern = try! NSRegularExpression(
            pattern: "@IBAction\\b|\\.addTarget\\s*\\(",
            options: []
        )
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        let functionMatches = functionPattern.matches(in: text, options: [], range: range)
        let functions: [FunctionMetric] = functionMatches.enumerated().compactMap { idx, match in
            guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[nameRange])
            let startLine = SnippetBuilder.lineNumber(in: text, utf16Offset: match.range.location)
            let nextLocation = idx + 1 < functionMatches.count ? functionMatches[idx + 1].range.location : nil
            let endLine = estimatedFunctionEndLine(
                text: text,
                declarationLocation: match.range.location,
                nextDeclarationLocation: nextLocation
            )
            let hasBody = endLine > startLine
            return FunctionMetric(name: name, startLine: startLine, endLine: endLine, hasBody: hasBody)
        }

        var typeNames: [String] = []
        for match in typePattern.matches(in: text, options: [], range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            if !typeNames.contains(name) {
                typeNames.append(name)
            }
        }

        let extensionCount = extensionPattern.numberOfMatches(in: text, options: [], range: range)
        let uiActionCount = uiActionPattern.numberOfMatches(in: text, options: [], range: range)
        let bodyFunctionCount = functions.filter(\.hasBody).count
        let markSections = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("// MARK:") else { return nil }
            return trimmed.replacingOccurrences(of: "// MARK:", with: "").trimmingCharacters(in: .whitespaces)
        }
        return FileAnalysis(
            lineCount: lineCount,
            functions: functions,
            typeNames: typeNames,
            extensionCount: extensionCount,
            uiActionCount: uiActionCount,
            bodyFunctionCount: bodyFunctionCount,
            markSections: markSections
        )
    }

    private func estimatedFunctionEndLine(
        text: String,
        declarationLocation: Int,
        nextDeclarationLocation: Int?
    ) -> Int {
        let bytes = Array(text.utf16)
        if bytes.isEmpty {
            return 1
        }
        let start = min(max(declarationLocation, 0), bytes.count - 1)
        let limit = min(nextDeclarationLocation ?? bytes.count, bytes.count)
        if start >= limit {
            return SnippetBuilder.lineNumber(in: text, utf16Offset: start)
        }

        var index = start
        var sawOpeningBrace = false
        var braceDepth = 0
        var lookaheadLines = 0
        var lastNewlineIndex = start

        while index < limit {
            let scalar = bytes[index]
            if scalar == 10 {
                lookaheadLines += 1
                lastNewlineIndex = index
            }
            if scalar == 123 {
                sawOpeningBrace = true
                braceDepth += 1
            } else if scalar == 125, sawOpeningBrace {
                braceDepth -= 1
                if braceDepth == 0 {
                    return SnippetBuilder.lineNumber(in: text, utf16Offset: index)
                }
            }
            if !sawOpeningBrace && lookaheadLines >= 6 {
                return SnippetBuilder.lineNumber(in: text, utf16Offset: lastNewlineIndex)
            }
            index += 1
        }
        return SnippetBuilder.lineNumber(in: text, utf16Offset: max(start, limit - 1))
    }

    private func countingConfidence(analysis: FileAnalysis) -> String {
        guard !analysis.functions.isEmpty else { return "low" }
        let bodyRatio = Double(analysis.bodyFunctionCount) / Double(analysis.functions.count)
        if bodyRatio < 0.6 { return "low" }
        if bodyRatio < 0.85 { return "medium" }
        return "high"
    }

    private func groupedFunctionPrefixes(from functions: [FunctionMetric]) -> [(prefix: String, count: Int)] {
        let interestingPrefixes = ["setup", "bind", "fetch", "handle", "validate", "load", "make", "build"]
        var counts: [String: Int] = [:]
        for function in functions {
            let lower = function.name.lowercased()
            if let match = interestingPrefixes.first(where: { lower.hasPrefix($0) }) {
                counts[match, default: 0] += 1
            }
        }
        return counts.map { (prefix: $0.key, count: $0.value) }.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.prefix < rhs.prefix }
            return lhs.count > rhs.count
        }
    }

    private struct FunctionMetric {
        let name: String
        let startLine: Int
        let endLine: Int
        let hasBody: Bool

        var lineSpan: Int {
            max(1, endLine - startLine + 1)
        }
    }

    private struct FileAnalysis {
        let lineCount: Int
        let functions: [FunctionMetric]
        let typeNames: [String]
        let extensionCount: Int
        let uiActionCount: Int
        let bodyFunctionCount: Int
        let markSections: [String]
    }
}
