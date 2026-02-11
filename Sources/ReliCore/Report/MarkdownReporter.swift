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
        // Group findings by severity.
        let grouped = Dictionary(grouping: findings) { $0.severity }
        // Sort severities high to low.
        let severities: [Severity] = [.high, .medium, .low, .info]
        var lines: [String] = []
        lines.append("## AIRefactorLint Report")
        lines.append("")
        if findings.isEmpty {
            lines.append("_No issues detected by enabled rules._")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        for severity in severities {
            guard let group = grouped[severity], !group.isEmpty else { continue }
            lines.append("### \(severity.rawValue.capitalized) Issues")
            lines.append("")
            for finding in group {
                var line = "- **\(finding.title)** in `\(finding.filePath)`"
                if let typeName = finding.typeName {
                    line += " [\(typeName)]"
                }
                if let lineNumber = finding.line {
                    line += ":\(lineNumber)"
                }
                line += " – \(finding.message)"
                lines.append(line)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
