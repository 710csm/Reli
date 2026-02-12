import Foundation

/// Generates a simple Markdown report from a collection of findings. The
/// report groups findings by severity and includes the filename and message
/// for each item. In a future release this reporter could be extended to
/// include AI‑generated explanations and fix suggestions.
public struct MarkdownReporter {
    
    public init() { }
    
    /// Produces a Markdown string summarising the findings. Findings are
    /// grouped by severity in descending order (high → info). Within each
    /// group the findings retain the order in which they were produced by
    /// the linter.
    ///
    /// - Parameter findings: The findings to summarise.
    /// - Returns: A Markdown document detailing the issues.
    public func report(findings: [Finding]) -> String {
        report(findings: findings, swiftFileCount: nil, inlineAI: [:])
    }

    /// Produces a Markdown report with a compact machine summary and optional
    /// per-finding inline AI explanations.
    public func report(
        findings: [Finding],
        swiftFileCount: Int?,
        inlineAI: [Int: String],
        totalFindings: Int? = nil,
        aiStatus: String? = nil
    ) -> String {
        // Group findings by severity.
        let indexedFindings = Array(findings.enumerated())
        let grouped = Dictionary(grouping: indexedFindings) { $0.element.severity }
        // Sort severities high to low.
        let severities: [Severity] = [.high, .medium, .low, .info]
        var lines: [String] = []
        lines.append("## AIRefactorLint Report")
        lines.append("")
        lines.append(
            contentsOf: summaryLines(
                findings: findings,
                swiftFileCount: swiftFileCount,
                totalFindings: totalFindings,
                aiStatus: aiStatus
            )
        )
        lines.append("")
        if findings.isEmpty {
            lines.append("_No issues detected by enabled rules._")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        var findingNumber = 0
        for severity in severities {
            guard let group = grouped[severity], !group.isEmpty else { continue }
            lines.append("### \(severity.rawValue.capitalized)")
            lines.append("")
            for (originalIndex, finding) in group {
                findingNumber += 1
                lines.append("#### Finding \(findingNumber): \(finding.title)")
                var metaLine = "- File: `\(finding.filePath)`"
                if let typeName = finding.typeName {
                    metaLine += " [\(typeName)]"
                }
                if let lineNumber = finding.line {
                    metaLine += ":\(lineNumber)"
                }
                if let countingMethod = finding.evidence["countingMethod"], !countingMethod.isEmpty {
                    metaLine += " (Counting method: \(countingMethod)"
                    if let confidence = finding.evidence["countingConfidence"], !confidence.isEmpty {
                        metaLine += ", Confidence: \(confidence)"
                    }
                    metaLine += ")"
                }
                lines.append(metaLine)
                lines.append("- Message: \(finding.message)")
                lines.append("- Evidence:")
                lines.append(contentsOf: evidenceLines(from: finding.evidence))
                if let aiText = inlineAI[originalIndex], !aiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("- AI Analysis:")
                    aiText.split(separator: "\n", omittingEmptySubsequences: false).forEach {
                        lines.append("  \($0)")
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func summaryLines(
        findings: [Finding],
        swiftFileCount: Int?,
        totalFindings: Int?,
        aiStatus: String?
    ) -> [String] {
        let high = findings.filter { $0.severity == .high }.count
        let medium = findings.filter { $0.severity == .medium }.count
        let low = findings.filter { $0.severity == .low }.count
        let info = findings.filter { $0.severity == .info }.count
        let rules = Array(Set(findings.map(\.ruleID))).sorted().joined(separator: ", ")
        let total = totalFindings ?? findings.count

        var lines = [
            "- Summary: machine-generated findings overview",
            "- Swift files scanned: \(swiftFileCount.map(String.init) ?? "n/a")",
            "- Total findings: \(total)",
            "- Severity breakdown: high \(high), medium \(medium), low \(low), info \(info)",
            "- Rules triggered: \(rules.isEmpty ? "none" : rules)"
        ]
        if let aiStatus, !aiStatus.isEmpty {
            lines.append("- AI: \(aiStatus)")
        }
        lines.append("- Top 5 files by findings: \(topFilesSummary(from: findings))")
        lines.append("- Top 5 types by size: \(topTypesSummary(from: findings))")
        return lines
    }

    private func evidenceLines(from evidence: [String: String]) -> [String] {
        if evidence.isEmpty {
            return ["  - none"]
        }
        return evidence
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "  - \($0.key): \($0.value)" }
    }

    private func topFilesSummary(from findings: [Finding], limit: Int = 5) -> String {
        let ranked = Dictionary(grouping: findings, by: \.filePath)
            .map { (file: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.file < rhs.file }
                return lhs.count > rhs.count
            }
            .prefix(limit)

        guard !ranked.isEmpty else { return "none" }
        return ranked
            .map { "\($0.file) (\($0.count))" }
            .joined(separator: " | ")
    }

    private func topTypesSummary(from findings: [Finding], limit: Int = 5) -> String {
        var largestByType: [String: Int] = [:]
        for finding in findings {
            guard let typeName = finding.typeName, !typeName.isEmpty else { continue }
            guard let lineCountText = finding.evidence["lineCount"], let lineCount = Int(lineCountText) else { continue }
            largestByType[typeName] = max(largestByType[typeName] ?? 0, lineCount)
        }

        let ranked = largestByType
            .map { (type: $0.key, lineCount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.lineCount == rhs.lineCount { return lhs.type < rhs.type }
                return lhs.lineCount > rhs.lineCount
            }
            .prefix(limit)

        guard !ranked.isEmpty else { return "none" }
        return ranked
            .map { "\($0.type) (\($0.lineCount)L)" }
            .joined(separator: " | ")
    }
}
