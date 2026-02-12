import Foundation
import ReliCore

/// Helper utilities extracted from `ReliCommand` to keep the command flow
/// readable and focused on orchestration.
extension ReliCommand {
    /// Caps output findings while preserving existing ordering.
    func applyMaxFindings(to findings: [Finding]) -> [Finding] {
        guard let maxFindings else { return findings }
        return Array(findings.prefix(maxFindings))
    }

    /// Sorts findings by severity first, then stable path/line/title ordering.
    func prioritize(_ findings: [Finding]) -> [Finding] {
        findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            let lhsLine = lhs.line ?? Int.max
            let rhsLine = rhs.line ?? Int.max
            if lhsLine != rhsLine { return lhsLine < rhsLine }
            return lhs.title < rhs.title
        }
    }

    /// Rewrites finding file paths according to the selected path style.
    func applyPathStyle(to findings: [Finding], rootPath: String) -> [Finding] {
        findings.map { finding in
            let renderedPath: String
            switch pathStyle {
            case .absolute:
                renderedPath = URL(fileURLWithPath: finding.filePath).standardizedFileURL.path
            case .relative:
                renderedPath = makeRelativePath(finding.filePath, rootPath: rootPath)
            }
            return Finding(
                ruleID: finding.ruleID,
                title: finding.title,
                message: finding.message,
                severity: finding.severity,
                filePath: renderedPath,
                line: finding.line,
                column: finding.column,
                typeName: finding.typeName,
                evidence: finding.evidence,
                snippet: finding.snippet
            )
        }
    }

    /// Converts an absolute path to a root-relative path when possible.
    func makeRelativePath(_ filePath: String, rootPath: String) -> String {
        let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let standardizedFile = URL(fileURLWithPath: filePath).standardizedFileURL.path
        if standardizedFile.hasPrefix(standardizedRoot + "/") {
            return String(standardizedFile.dropFirst(standardizedRoot.count + 1))
        }
        return filePath
    }

    /// Parses comma-separated input into a set.
    func parseCSVSet(_ csv: String?) -> Set<String> {
        Set(parseCSVList(csv))
    }

    /// Parses comma-separated input into a trimmed list.
    func parseCSVList(_ csv: String?) -> [String] {
        guard let csv, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Filters findings using glob-like path exclude patterns.
    func applyExcludePaths(to findings: [Finding], rootPath: String, patterns: [String]) -> [Finding] {
        guard !patterns.isEmpty else { return findings }
        return findings.filter { finding in
            let relative = makeRelativePath(finding.filePath, rootPath: rootPath)
            return !patterns.contains { pattern in
                globMatch(relative, pattern: pattern)
            }
        }
    }

    /// Minimal glob matcher supporting `*`, `**`, and `?`.
    func globMatch(_ path: String, pattern: String) -> Bool {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        var p = pattern.replacingOccurrences(of: "\\", with: "/")
        if p.hasPrefix("/") {
            p = String(p.dropFirst())
        }
        if p.hasPrefix("./") {
            p = String(p.dropFirst(2))
        }

        var regex = "^"
        var idx = p.startIndex
        while idx < p.endIndex {
            let ch = p[idx]
            if ch == "*" {
                let next = p.index(after: idx)
                if next < p.endIndex, p[next] == "*" {
                    regex += ".*"
                    idx = p.index(after: next)
                } else {
                    regex += "[^/]*"
                    idx = next
                }
                continue
            }
            if ch == "?" {
                regex += "[^/]"
                idx = p.index(after: idx)
                continue
            }
            if ".+()[]{}|^$\\".contains(ch) {
                regex += "\\"
            }
            regex.append(ch)
            idx = p.index(after: idx)
        }
        regex += "$"

        guard let re = try? NSRegularExpression(pattern: regex, options: []) else { return false }
        let range = NSRange(normalizedPath.startIndex..<normalizedPath.endIndex, in: normalizedPath)
        return re.firstMatch(in: normalizedPath, options: [], range: range) != nil
    }

    /// Default path exclusions used to suppress test/sample noise unless
    /// explicitly included by CLI flags.
    func defaultExcludedPathPatterns(includeTests: Bool, includeSamples: Bool) -> [String] {
        var patterns: [String] = []
        if !includeTests {
            patterns.append(contentsOf: [
                "*Tests*/**",
                "Tests/**",
                "**/*Tests*/**",
                "**/Tests/**"
            ])
        }
        if !includeSamples {
            patterns.append(contentsOf: [
                "*Sample*/**",
                "**/*Sample*/**",
                "Examples/**",
                "*/Examples/**",
                "**/Examples/**"
            ])
        }
        return patterns
    }
}
