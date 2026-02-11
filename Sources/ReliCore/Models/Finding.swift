import Foundation

/// Describes the severity of a lint finding. Higher severities indicate more
/// urgent problems. These values are used to group findings and to drive
/// reporting. Additional severities may be added in the future.
public enum Severity: String, Codable, Sendable, CaseIterable {
    case info
    case low
    case medium
    case high
}

extension Severity: Comparable {
    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        rank(of: lhs) < rank(of: rhs)
    }

    private static func rank(of severity: Severity) -> Int {
        switch severity {
        case .info: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}

/// Represents a single issue detected by one of the lint rules. Findings are
/// created by rule implementations and then aggregated by the linter. They
/// capture the origin of the problem, a human‑readable message, a severity,
/// optional location information, structured evidence and an optional code
/// snippet for context.
public struct Finding: Codable, Sendable {
    /// Identifier for the rule that produced this finding. Typically matches
    /// the rule's `id` property.
    public let ruleID: String
    /// Short title summarising the issue.
    public let title: String
    /// A descriptive message explaining what was found.
    public let message: String
    /// The perceived urgency of the issue.
    public let severity: Severity
    /// Path to the file containing the issue.
    public let filePath: String
    /// Optional one‑based line number where the issue was detected.
    public let line: Int?
    /// Optional one‑based column number corresponding to the issue.
    public let column: Int?
    /// Optional type name related to the finding (for example a VC/VM type).
    public let typeName: String?
    /// Arbitrary structured data captured by the rule. This might include
    /// counts of patterns, threshold values or other metrics used to trigger
    /// the finding.
    public let evidence: [String: String]
    /// An optional snippet of the source code providing context for the
    /// finding. When provided this should be a minimal excerpt sufficient to
    /// orient the reader.
    public let snippet: String?

    public init(
        ruleID: String,
        title: String,
        message: String,
        severity: Severity,
        filePath: String,
        line: Int? = nil,
        column: Int? = nil,
        typeName: String? = nil,
        evidence: [String: String] = [:],
        snippet: String? = nil
    ) {
        self.ruleID = ruleID
        self.title = title
        self.message = message
        self.severity = severity
        self.filePath = filePath
        self.line = line
        self.column = column
        self.typeName = typeName
        self.evidence = evidence
        self.snippet = snippet
    }
}
