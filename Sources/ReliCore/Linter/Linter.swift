import Foundation

/// Primary engine responsible for executing configured lint rules over a
/// `LintContext`. It aggregates the results from each rule and provides
/// simple reporting. The linter does not interpret the results beyond
/// combining them; interpretation and formatting is delegated to reporter
/// types.
public struct Linter {
    /// The rules that will be applied during linting. The order of this
    /// array determines the ordering of findings in the aggregated output.
    private let rules: [Rule]

    /// Creates a new linter with the provided rules.
    ///
    /// - Parameter rules: an array of rule implementations
    public init(rules: [Rule]) {
        self.rules = rules
    }

    /// Executes each rule against the supplied context and returns all
    /// findings.
    ///
    /// - Parameter context: the representation of the sources to analyse
    /// - Returns: an array of findings from all rules
    public func run(context: LintContext) throws -> [Finding] {
        var allFindings: [Finding] = []
        for rule in rules {
            let findings = try rule.check(context)
            allFindings.append(contentsOf: findings)
        }
        return allFindings
    }
}
