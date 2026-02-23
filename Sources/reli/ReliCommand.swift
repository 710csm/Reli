import Foundation
import ReliCore
import ReliRules
import ArgumentParser

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ReliCommand: AsyncParsableCommand {
    /// Top-level command metadata shown in `--help`.
    static let configuration = CommandConfiguration(
        abstract: "Lint a Swift package and optionally generate an AI‑powered refactoring report."
    )

    @Option(name: .shortAndLong, help: "Root path of the Swift package to lint.")
    var path: String?

    @Flag(name: .long, help: "Disable AI explanations and emit only raw findings.")
    var noAI: Bool = false

    @Option(name: .long, help: "Path to a YAML config file.")
    var config: String?

    @Flag(name: .customLong("print-config"), help: "Print the final merged config and exit.")
    var printConfig: Bool = false

    @Option(name: .long, help: "Comma separated list of rule identifiers to enable (default: all).")
    var rules: String?

    @Option(name: .customLong("ignore-rules"), help: "Comma separated list of rule identifiers to ignore.")
    var ignoreRules: String?

    @Option(name: .customLong("ignore-paths"), help: "Comma separated glob patterns for file paths to ignore (e.g. Sources/Utils/**).")
    var ignorePaths: String?

    @Option(name: .customLong("exclude-paths"), help: "Comma separated glob patterns for file paths to exclude (e.g. Sources/Utils/**).")
    var excludePaths: String?

    @Option(name: .long, help: "Output format: markdown or json.")
    var format: String?

    @Option(name: .long, help: "Write output to the specified file instead of stdout.")
    var out: String?

    @Option(name: .long, help: "Specify an OpenAI model (e.g. gpt-4o-mini, gpt-4.1-mini).")
    var model: String?

    @Option(name: .long, help: "Maximum number of findings to send to AI for explanations.")
    var aiLimit: Int?

    @Option(
        name: .customLong("di-singleton-allowlist"),
        help: "Comma separated singleton access entries to ignore in di-smell (e.g. NotificationCenter.default,FileManager.default)."
    )
    var diSingletonAllowlist: String = "NotificationCenter.default,FileManager.default"

    @Option(
        name: .customLong("fail-on"),
        help: "Exit with code 1 if findings are at or above the given severity (off|low|medium|high)."
    )
    var failOn: FailOn?

    @Option(
        name: .customLong("annotations"),
        help: "Emit CI annotations (off|github)."
    )
    var annotations: AnnotationsMode?

    @Option(
        name: .customLong("include-extensions"),
        help: "Include same-file extensions in type-level analysis (true|false)."
    )
    var includeExtensions: Bool?

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
    var pathStyle: PathStyle?

    /// Executes lint analysis, emits report output, then applies CI-oriented
    /// behaviors such as annotations and fail-on thresholds.
    func run() async throws {
        let options = try resolveEffectiveOptions()

        if printConfig {
            try printEffectiveConfig(options)
            return
        }

        if let maxFindings = options.maxFindings, maxFindings < 1 {
            throw ValidationError("--max-findings must be a positive integer.")
        }
        if options.aiLimit < 0 {
            throw ValidationError("--ai-limit must be zero or a positive integer.")
        }

        // Normalize the root path so report paths + annotations are stable.
        let rootURL = URL(fileURLWithPath: options.path).standardizedFileURL
        let rootPath = rootURL.path
        let ignoredRuleIDs = parseCSVSet(ignoreRules)
        let singletonAllowlist = parseCSVSet(diSingletonAllowlist)

        // Discover Swift files and build the lint context.
        let walker = FileWalker()
        let context: LintContext
        do {
            context = try walker.walk(root: rootPath, excludedPathPatterns: options.excludePaths)
        } catch {
            throw ValidationError("Failed to walk directory: \(error.localizedDescription)")
        }
        // Build rule list.
        var selectedRules: [Rule] = []
        let allRules: [Rule] = [
            GodTypeRule(includeExtensions: options.includeExtensions),
            DependencyInjectionSmellRule(singletonAllowlist: singletonAllowlist),
            AsyncLifecycleRule()
        ]
        switch options.rules {
        case .all:
            selectedRules = allRules
        case .list(let configuredRuleIDs):
            let ids = Set(configuredRuleIDs)
            selectedRules = allRules.filter { ids.contains($0.id) }
            if selectedRules.isEmpty {
                throw ValidationError("No matching rules for configured rules (\(configuredRuleIDs.joined(separator: ","))). Available: \(allRules.map(\.id).joined(separator: ", "))")
            }
        }
        if !ignoredRuleIDs.isEmpty {
            selectedRules.removeAll { ignoredRuleIDs.contains($0.id) }
        }
        // Run linter.
        let linter = Linter(rules: selectedRules)
        let findings = try linter.run(context: context)
        let prioritizedFindings = prioritize(findings)
        let cappedFindings = applyMaxFindings(to: prioritizedFindings, maxFindings: options.maxFindings)
        let reportFindings = applyPathStyle(to: cappedFindings, rootPath: rootPath, pathStyle: options.pathStyle)
        let omittedFindingsCount = max(0, prioritizedFindings.count - reportFindings.count)
        // Build report output (JSON or Markdown with optional AI augmentation).
        var output: String
        switch options.format.lowercased() {
        case "json":
            let reporter = JSONReporter()
            output = try reporter.report(findings: reportFindings)
        default:
            // Markdown with or without inline AI explanations.
            let reporter = MarkdownReporter()
            var inlineAI: [Int: String] = [:]
            var aiStatus: String?
            var aiPlannedCalls: Int? = 0
            if options.noAI {
                aiStatus = "disabled (--no-ai)"
            } else {
                aiPlannedCalls = min(options.aiLimit, reportFindings.count)
                let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if apiKey.isEmpty {
                    aiStatus = "disabled (OPENAI_API_KEY not set)"
                    aiPlannedCalls = 0
                } else {
                    // Build iOS-focused prompts per finding and render responses inline.
                    let provider = OpenAIProvider(apiKey: apiKey, model: options.model)
                    let projectName = rootURL.lastPathComponent
                    let aiIndices = AILimitSelector.selectedIndices(
                        totalFindings: reportFindings.count,
                        limit: options.aiLimit
                    )
                    aiPlannedCalls = aiIndices.count
                    for (position, index) in aiIndices.enumerated() {
                        let finding = reportFindings[index]
                        let lineText = finding.line.map(String.init) ?? "?"
                        fputs(
                            "[reli][ai] request \(position + 1)/\(aiIndices.count): \(finding.filePath):\(lineText) \(finding.title)\n",
                            stderr
                        )
                        let prompt = Prompt.explainFinding(
                            finding: finding,
                            projectName: projectName,
                            findingNumber: position + 1,
                            totalFindings: aiIndices.count
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
                aiStatus: aiStatus,
                aiCallLimit: options.aiLimit,
                aiPlannedCalls: aiPlannedCalls
            )
            if omittedFindingsCount > 0 {
                output += "\n\n_Note: Showing top \(reportFindings.count) of \(prioritizedFindings.count) findings (`--max-findings \(reportFindings.count)`)._"
            }
        }
        // Write or print output.
        if let outFile = options.out {
            let url = URL(fileURLWithPath: outFile)
            try output.write(to: url, atomically: true, encoding: .utf8)
        } else {
            print(output)
        }

        if options.annotations == .github {
            GitHubAnnotationsEmitter(projectRoot: rootPath, normalizeRelativePaths: options.pathStyle == .relative)
                .emit(findings: reportFindings)
        }

        if let threshold = options.failOn.threshold {
            let shouldFail = findings.contains { $0.severity >= threshold }
            if shouldFail {
                throw ExitCode.failure
            }
        }
    }
}
