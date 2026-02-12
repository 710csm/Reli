import Foundation
import ReliCore

extension ReliCommand {
    func applyMaxFindings(to findings: [Finding]) -> [Finding] {
        guard let maxFindings else { return findings }
        return Array(findings.prefix(maxFindings))
    }

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

    func makeRelativePath(_ filePath: String, rootPath: String) -> String {
        let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let standardizedFile = URL(fileURLWithPath: filePath).standardizedFileURL.path
        if standardizedFile.hasPrefix(standardizedRoot + "/") {
            return String(standardizedFile.dropFirst(standardizedRoot.count + 1))
        }
        return filePath
    }

    func parseCSVSet(_ csv: String?) -> Set<String> {
        Set(parseCSVList(csv))
    }

    func parseCSVList(_ csv: String?) -> [String] {
        guard let csv, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func applyExcludePaths(to findings: [Finding], rootPath: String, patterns: [String]) -> [Finding] {
        guard !patterns.isEmpty else { return findings }
        return findings.filter { finding in
            let relative = makeRelativePath(finding.filePath, rootPath: rootPath)
            return !patterns.contains { pattern in
                globMatch(relative, pattern: pattern)
            }
        }
    }

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
