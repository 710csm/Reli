import Foundation

/// Factory for constructing AI prompts from lint findings. This separates
/// prompt construction from AI invocation to simplify testing and allow
/// alternative prompt formats. The generated prompt instructs the AI on
/// how to format the report and includes all necessary data about the
/// findings.
public struct Prompt {
    /// Constructs a prompt suitable for an AI provider given a list of
    /// findings and a project name. The prompt instructs the AI to produce
    /// an actionable refactoring report in Markdown.
    ///
    /// - Parameters:
    ///   - findings: The lint findings to explain.
    ///   - projectName: The name of the project being analysed.
    /// - Returns: A textual prompt.
    public static func explain(findings: [Finding], projectName: String) -> String {
        // Build a YAML‑like summary of findings to embed in the prompt. Each
        // finding includes the rule identifier, title, severity, file path
        // and evidence. Optionally a snippet is included if available.
        let compact = findings.map { finding -> String in
            var lines: [String] = []
            lines.append("- ruleID: \(finding.ruleID)")
            lines.append("  title: \(finding.title)")
            lines.append("  severity: \(finding.severity.rawValue)")
            let lineSuffix = finding.line.map { ":\($0)" } ?? ""
            lines.append("  file: \(finding.filePath)\(lineSuffix)")
            lines.append("  message: \(finding.message)")
            lines.append("  evidence: \(finding.evidence)")
            if let snippet = finding.snippet {
                lines.append("  snippet: |")
                // Indent each line of the snippet to preserve formatting in YAML
                snippet.split(separator: "\n", omittingEmptySubsequences: false)
                    .forEach { lines.append("    \($0)") }
            } else {
                lines.append("  snippet: null")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")

        return """
You are a senior iOS engineer reviewing a Swift codebase named \(projectName).
Produce an actionable refactoring report in Markdown.

Requirements:
- Group issues by severity (high → low).
- For each issue: explain the likely root cause, why it matters, and propose 1–3 concrete refactoring steps.
- Provide a short code example only if confident; keep examples minimal.
- Include a "Risk & Verification" checklist for each issue.
- Be specific to iOS/Swift best practices. Avoid generic advice.

Findings:
\(compact)
"""
    }
}
