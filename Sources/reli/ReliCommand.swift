import Foundation
import ReliCore
import ReliRules
import ArgumentParser

enum FailOn: String, ExpressibleByArgument {
    case off
    case low
    case medium
    case high

    var threshold: Severity? {
        switch self {
        case .off:
            return nil
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }
}

enum AnnotationsMode: String, ExpressibleByArgument {
    case off
    case github
}

enum PathStyle: String, ExpressibleByArgument {
    case relative
    case absolute
}

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ReliCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lint a Swift package and optionally generate an AI‑powered refactoring report."
    )

    @Option(name: .shortAndLong, help: "Root path of the Swift package to lint.")
    var path: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Disable AI explanations and emit only raw findings.")
    var noAI: Bool = false

    @Option(name: .long, help: "Comma separated list of rule identifiers to enable (default: all).")
    var rules: String?

    @Option(name: .customLong("ignore-rules"), help: "Comma separated list of rule identifiers to ignore.")
    var ignoreRules: String?

    @Option(name: .customLong("ignore-paths"), help: "Comma separated glob patterns for file paths to ignore (e.g. Sources/Utils/**).")
    var ignorePaths: String?

    @Option(name: .customLong("exclude-paths"), help: "Comma separated glob patterns for file paths to exclude (e.g. Sources/Utils/**).")
    var excludePaths: String?

    @Option(name: .long, help: "Output format: markdown or json.")
    var format: String = "markdown"

    @Option(name: .long, help: "Write output to the specified file instead of stdout.")
    var out: String?

    @Option(name: .long, help: "Specify an OpenAI model (e.g. gpt-4o-mini, gpt-4.1-mini).")
    var model: String = "gpt-4o-mini"

    @Option(
        name: .customLong("di-singleton-allowlist"),
        help: "Comma separated singleton access entries to ignore in di-smell (e.g. NotificationCenter.default,FileManager.default)."
    )
    var diSingletonAllowlist: String = "NotificationCenter.default,FileManager.default"

    @Option(
        name: .customLong("fail-on"),
        help: "Exit with code 1 if findings are at or above the given severity (off|low|medium|high)."
    )
    var failOn: FailOn = .off

    @Option(
        name: .customLong("annotations"),
        help: "Emit CI annotations (off|github)."
    )
    var annotations: AnnotationsMode = .off

    @Option(
        name: .customLong("include-extensions"),
        help: "Include same-file extensions in type-level analysis (true|false)."
    )
    var includeExtensions: Bool = false

    @Flag(name: .customLong("include-tests"), help: "Include test paths in analysis output.")
    var includeTests: Bool = false

    @Flag(name: .customLong("include-samples"), help: "Include sample/example paths in analysis output.")
    var includeSamples: Bool = false

    @Option(
        name: .customLong("max-findings"),
        help: "Limit report/annotation output to the top N findings."
    )
    var maxFindings: Int?

    @Option(
        name: .customLong("path-style"),
        help: "Render file paths as absolute or repo-relative (absolute|relative)."
    )
    var pathStyle: PathStyle = .relative

    func run() async throws {
        if let maxFindings, maxFindings < 1 {
            throw ValidationError("--max-findings must be a positive integer.")
        }

        // Normalize the root path so report paths + annotations are stable.
        let rootURL = URL(fileURLWithPath: path).standardizedFileURL
        let rootPath = rootURL.path
        let ignoredRuleIDs = parseCSVSet(ignoreRules)
        var excludedPathPatterns = defaultExcludedPathPatterns(
            includeTests: includeTests,
            includeSamples: includeSamples
        )
        excludedPathPatterns.append(contentsOf: parseCSVList(ignorePaths))
        excludedPathPatterns.append(contentsOf: parseCSVList(excludePaths))
        let singletonAllowlist = parseCSVSet(diSingletonAllowlist)

        // Discover Swift files and build the lint context.
        let walker = FileWalker()
        let context: LintContext
        do {
            context = try walker.walk(root: rootPath)
        } catch {
            throw ValidationError("Failed to walk directory: \(error.localizedDescription)")
        }
        // Build rule list.
        var selectedRules: [Rule] = []
        let allRules: [Rule] = [
            GodTypeRule(includeExtensions: includeExtensions),
            DependencyInjectionSmellRule(singletonAllowlist: singletonAllowlist),
            AsyncLifecycleRule()
        ]
        if let rulesCSV = rules {
            let ids = Set(rulesCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            selectedRules = allRules.filter { ids.contains($0.id) }
            if selectedRules.isEmpty {
                throw ValidationError("No matching rules for --rules=\(rulesCSV). Available: \(allRules.map(\.id).joined(separator: ", "))")
            }
        } else {
            selectedRules = allRules
        }
        if !ignoredRuleIDs.isEmpty {
            selectedRules.removeAll { ignoredRuleIDs.contains($0.id) }
        }
        // Run linter.
        let linter = Linter(rules: selectedRules)
        let rawFindings = try linter.run(context: context)
        let findings = applyExcludePaths(to: rawFindings, rootPath: rootPath, patterns: excludedPathPatterns)
        let prioritizedFindings = prioritize(findings)
        let cappedFindings = applyMaxFindings(to: prioritizedFindings)
        let reportFindings = applyPathStyle(to: cappedFindings, rootPath: rootPath)
        let omittedFindingsCount = max(0, prioritizedFindings.count - reportFindings.count)
        // Build report.
        var output: String
        switch format.lowercased() {
        case "json":
            let reporter = JSONReporter()
            output = try reporter.report(findings: reportFindings)
        default:
            // Markdown with or without inline AI explanations.
            let reporter = MarkdownReporter()
            var inlineAI: [Int: String] = [:]
            var aiStatus: String?
            if !noAI {
                let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if apiKey.isEmpty {
                    aiStatus = "disabled (OPENAI_API_KEY not set)"
                } else {
                    // Build iOS-focused prompts per finding and render responses inline.
                    let provider = OpenAIProvider(apiKey: apiKey, model: model)
                    let projectName = rootURL.lastPathComponent
                    for (index, finding) in reportFindings.enumerated() {
                        let prompt = Prompt.explainFinding(
                            finding: finding,
                            projectName: projectName,
                            findingNumber: index + 1,
                            totalFindings: reportFindings.count
                        )
                        do {
                            let aiReport = try await provider.generateMarkdown(prompt: prompt)
                            inlineAI[index] = aiReport
                        } catch {
                            inlineAI[index] = "### Root Cause\nUnable to retrieve AI analysis.\n\n### Recommended Split Boundaries\n- Derive groups from function prefixes (setup*/bind*/fetch*/handle*/validate*) and // MARK: sections in evidence.\n\n### Refactoring Steps\n- Retry with network/API key configured.\n\n### Risk & Verification Checklist\n- Run Instruments Leaks while entering/exiting the screen.\n- Repeat push/pop or present/dismiss navigation flow.\n- Verify async teardown (deinit/task cancellation).\n- Verify UI updates occur on main thread.\n- Error: \(error.localizedDescription)"
                        }
                    }
                }
            }
            output = reporter.report(
                findings: reportFindings,
                swiftFileCount: context.swiftFiles.count,
                inlineAI: inlineAI,
                totalFindings: prioritizedFindings.count,
                aiStatus: aiStatus
            )
            if omittedFindingsCount > 0 {
                output += "\n\n_Note: Showing top \(reportFindings.count) of \(prioritizedFindings.count) findings (`--max-findings \(reportFindings.count)`)._"
            }
        }
        // Write or print output.
        if let outFile = out {
            let url = URL(fileURLWithPath: outFile)
            try output.write(to: url, atomically: true, encoding: .utf8)
        } else {
            print(output)
        }

        if annotations == .github {
            GitHubAnnotationsEmitter(projectRoot: rootPath, normalizeRelativePaths: pathStyle == .relative)
                .emit(findings: reportFindings)
        }

        if let threshold = failOn.threshold {
            let shouldFail = findings.contains { $0.severity >= threshold }
            if shouldFail {
                throw ExitCode.failure
            }
        }
    }

    private func applyMaxFindings(to findings: [Finding]) -> [Finding] {
        guard let maxFindings else { return findings }
        return Array(findings.prefix(maxFindings))
    }

    private func prioritize(_ findings: [Finding]) -> [Finding] {
        findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            let lhsLine = lhs.line ?? Int.max
            let rhsLine = rhs.line ?? Int.max
            if lhsLine != rhsLine { return lhsLine < rhsLine }
            return lhs.title < rhs.title
        }
    }

    private func applyPathStyle(to findings: [Finding], rootPath: String) -> [Finding] {
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

    private func makeRelativePath(_ filePath: String, rootPath: String) -> String {
        let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let standardizedFile = URL(fileURLWithPath: filePath).standardizedFileURL.path
        if standardizedFile.hasPrefix(standardizedRoot + "/") {
            return String(standardizedFile.dropFirst(standardizedRoot.count + 1))
        }
        return filePath
    }

    private func parseCSVSet(_ csv: String?) -> Set<String> {
        Set(parseCSVList(csv))
    }

    private func parseCSVList(_ csv: String?) -> [String] {
        guard let csv, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func applyExcludePaths(to findings: [Finding], rootPath: String, patterns: [String]) -> [Finding] {
        guard !patterns.isEmpty else { return findings }
        return findings.filter { finding in
            let relative = makeRelativePath(finding.filePath, rootPath: rootPath)
            return !patterns.contains { pattern in
                globMatch(relative, pattern: pattern)
            }
        }
    }

    private func globMatch(_ path: String, pattern: String) -> Bool {
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

    private func defaultExcludedPathPatterns(includeTests: Bool, includeSamples: Bool) -> [String] {
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
                "**/Examples/**",
                "Examples/**"
            ])
        }
        return patterns
    }
}
