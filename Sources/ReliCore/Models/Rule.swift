import Foundation

/// Protocol implemented by all lint rules. A rule examines a `LintContext`
/// representing the contents of a Swift package and produces zero or more
/// `Finding` instances describing potential issues.
public protocol Rule: Sendable {
    /// A unique identifier for the rule. This should be stable across
    /// releases so that consumers can enable/disable specific rules.
    var id: String { get }
    /// A human‑readable description of what the rule detects.
    var description: String { get }
    /// Performs analysis on the supplied context. Implementations should
    /// catch errors internally and rethrow only if analysis cannot proceed.
    ///
    /// - Parameter context: representation of the sources to analyse
    /// - Returns: an array of findings produced by this rule
    func check(_ context: LintContext) throws -> [Finding]
}
