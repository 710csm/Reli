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
            lines.append("  typeName: \(finding.typeName ?? "null")")
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

    /// Constructs an iOS-focused prompt for a single finding so the response
    /// can be rendered inline next to the machine-detected evidence.
    public static func explainFinding(
        finding: Finding,
        projectName: String,
        findingNumber: Int,
        totalFindings: Int
    ) -> String {
        let lineSuffix = finding.line.map { ":\($0)" } ?? ""
        var snippetBlock = "null"
        if let snippet = finding.snippet, !snippet.isEmpty {
            snippetBlock = snippet
        }

        return """
You are a senior iOS engineer reviewing finding \(findingNumber) of \(totalFindings) in project \(projectName).
Write concise, practical advice in Markdown with exactly these sections:
### Root Cause
### Recommended Split Boundaries
### Refactoring Steps
### Risk & Verification Checklist

Architecture priority rules:
- If this looks like a UIKit UIViewController context, prioritize Coordinator + ViewModel + UseCase boundaries.
- If this looks like a SwiftUI View context, prioritize ViewModel + Reducer boundaries.
- If this looks like utility/helper logic, prioritize extension extraction first before introducing new layers.
- For navigation-heavy screen logic, prefer Router/NavigationHandler; for list screens, consider SectionBuilder/DataSource split.
- For network/business logic, prefer Service/Client/Interactor split.

Keep recommendations specific to the finding evidence and avoid generic textbook advice.
Propose 1-3 concrete steps with extraction boundaries named from existing symbols when possible.
For Recommended Split Boundaries, propose grouping candidates using:
- function name prefixes such as setup*/bind*/fetch*/handle*/validate*
- existing // MARK: sections when available

For Risk & Verification Checklist, include concrete iOS checks (adapt to relevance):
- memory leak check on enter/exit using Instruments Leaks
- navigation path stability (repeated push/pop or present/dismiss)
- async cancellation on teardown (deinit and task cancellation path)
- main-thread UI access verification (@MainActor/DispatchQueue.main)

Finding:
- ruleID: \(finding.ruleID)
- title: \(finding.title)
- severity: \(finding.severity.rawValue)
- file: \(finding.filePath)\(lineSuffix)
- typeName: \(finding.typeName ?? "null")
- message: \(finding.message)
- evidence: \(finding.evidence)
- snippet:
\(snippetBlock)
"""
    }
}
