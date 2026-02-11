import Foundation
import ReliCore

/// Flags types that are likely doing too much. This implementation uses a
/// SwiftSyntax-backed heuristic based on the number of lines and functions in
/// each type declaration. This reduces regex false positives and makes
/// type-level findings actionable.
public struct GodTypeRule: Rule {
    public let id = "god-type"
    public let description = "Detects overly large types (e.g. view controllers or view models)"
    
    private let lineThreshold: Int
    private let functionThreshold: Int
    private let includeExtensions: Bool

    /// - Parameters:
    ///   - lineThreshold: Triggers when a type exceeds this many lines.
    ///   - functionThreshold: Triggers when a type exceeds this many function declarations.
    ///   - includeExtensions: Whether same-file extensions should be merged into type metrics.
    ///
    /// Defaults are intentionally set to be a bit more sensitive so that most
    /// real-world codebases surface a manageable set of actionable findings.
    public init(lineThreshold: Int = 300, functionThreshold: Int = 20, includeExtensions: Bool = false) {
        self.lineThreshold = lineThreshold
        self.functionThreshold = functionThreshold
        self.includeExtensions = includeExtensions
    }

    public func check(_ context: LintContext) throws -> [Finding] {
        let analyzer = TypeAnalyzer()
        let metrics = includeExtensions
            ? aggregatedTypeMetrics(context: context, analyzer: analyzer)
            : perFileTypeMetrics(context: context, analyzer: analyzer)

        var findings: [Finding] = []
        for metric in metrics {
            let lineCount = metric.lineCount
            let funcCount = metric.functions.count
            guard lineCount >= lineThreshold || funcCount >= functionThreshold else { continue }

            let severity: Severity = (lineCount >= max(lineThreshold * 2, 600) || funcCount >= max(functionThreshold * 2, 40)) ? .high : .medium
            let snippet = SnippetBuilder.around(text: metric.sourceText, line: metric.startLine)
            let topFunctions = metric.functions
                .sorted { lhs, rhs in
                    if lhs.lineSpan == rhs.lineSpan { return lhs.startLine < rhs.startLine }
                    return lhs.lineSpan > rhs.lineSpan
                }
                .prefix(10)
                .map { "\($0.name)(\($0.lineSpan)L)" }
                .joined(separator: ", ")
            let avgFunctionLines = averageFunctionLines(metric.functions)
            let maxFunctionLines = metric.functions.map(\.lineSpan).max() ?? 0
            let prefixGroups = groupedFunctionPrefixes(from: metric.functions)
                .prefix(8)
                .map { "\($0.prefix): \($0.count)" }
                .joined(separator: ", ")
            let markSections = metric.markSections.prefix(8).joined(separator: ", ")
            let message = "\(metric.kind.capitalized) `\(metric.name)` appears large (\(lineCount) lines, \(funcCount) functions by SwiftSyntax counting). Consider splitting responsibilities by feature boundaries. Counting method: swift-syntax (v0.2), confidence: high."

            findings.append(
                Finding(
                    ruleID: id,
                    title: "Massive type suspected",
                    message: message,
                    severity: severity,
                    filePath: metric.filePath,
                    line: metric.startLine,
                    column: nil,
                    typeName: metric.name,
                    evidence: [
                        "lineCount": "\(lineCount)",
                        "funcCount": "\(funcCount)",
                        "lineThreshold": "\(lineThreshold)",
                        "functionThreshold": "\(functionThreshold)",
                        "typeName": metric.name,
                        "typeKind": metric.kind,
                        "topFunctionNames": topFunctions,
                        "avgFunctionLines": avgFunctionLines,
                        "maxFunctionLines": "\(maxFunctionLines)",
                        "extensionCount": "\(metric.extensionCount)",
                        "includeExtensions": "\(includeExtensions)",
                        "uiActionCount": "\(metric.uiActionCount)",
                        "functionPrefixGroups": prefixGroups.isEmpty ? "none" : prefixGroups,
                        "markSections": markSections.isEmpty ? "none" : markSections,
                        "countingMethod": "swift-syntax (v0.2)",
                        "countingConfidence": "high"
                    ],
                    snippet: snippet
                )
            )
        }
        return findings
    }

    private func perFileTypeMetrics(context: LintContext, analyzer: TypeAnalyzer) -> [AnalyzedTypeMetric] {
        var output: [AnalyzedTypeMetric] = []
        for (path, text) in context.fileContents {
            guard path.hasSuffix(".swift") else { continue }
            let types = analyzer.analyze(filePath: path, source: text, includeExtensions: includeExtensions)
            for type in types {
                output.append(
                    AnalyzedTypeMetric(
                        name: type.name,
                        kind: type.kind,
                        filePath: path,
                        sourceText: text,
                        startLine: type.startLine,
                        lineCount: type.lineCount,
                        functions: type.functions,
                        extensionCount: type.extensionCount,
                        uiActionCount: type.uiActionCount,
                        markSections: type.markSections
                    )
                )
            }
        }
        return output
    }

    private func aggregatedTypeMetrics(context: LintContext, analyzer: TypeAnalyzer) -> [AnalyzedTypeMetric] {
        var order: [String] = []
        var merged: [String: AnalyzedTypeMetric] = [:]

        for (path, text) in context.fileContents {
            guard path.hasSuffix(".swift") else { continue }
            let types = analyzer.analyze(filePath: path, source: text, includeExtensions: true)
            for type in types {
                let key = type.name
                if var existing = merged[key] {
                    existing.lineCount += type.lineCount
                    existing.functions.append(contentsOf: type.functions)
                    existing.extensionCount += type.extensionCount
                    existing.uiActionCount += type.uiActionCount
                    existing.markSections.append(contentsOf: type.markSections)
                    if existing.kind == "extension", type.kind != "extension" {
                        existing.kind = type.kind
                        existing.filePath = path
                        existing.sourceText = text
                        existing.startLine = type.startLine
                    }
                    merged[key] = existing
                } else {
                    order.append(key)
                    merged[key] = AnalyzedTypeMetric(
                        name: type.name,
                        kind: type.kind,
                        filePath: path,
                        sourceText: text,
                        startLine: type.startLine,
                        lineCount: type.lineCount,
                        functions: type.functions,
                        extensionCount: type.extensionCount,
                        uiActionCount: type.uiActionCount,
                        markSections: type.markSections
                    )
                }
            }
        }

        return order.compactMap { merged[$0] }
    }

    private func averageFunctionLines(_ functions: [TypeFunctionMetric]) -> String {
        guard !functions.isEmpty else { return "0.0" }
        let total = functions.reduce(0) { $0 + $1.lineSpan }
        return String(format: "%.1f", Double(total) / Double(functions.count))
    }

    private func groupedFunctionPrefixes(from functions: [TypeFunctionMetric]) -> [(prefix: String, count: Int)] {
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

    private struct AnalyzedTypeMetric {
        let name: String
        var kind: String
        var filePath: String
        var sourceText: String
        var startLine: Int
        var lineCount: Int
        var functions: [TypeFunctionMetric]
        var extensionCount: Int
        var uiActionCount: Int
        var markSections: [String]
    }
}
