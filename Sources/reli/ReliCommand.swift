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

    @Option(name: .long, help: "Output format: markdown or json.")
    var format: String = "markdown"

    @Option(name: .long, help: "Write output to the specified file instead of stdout.")
    var out: String?

    @Option(name: .long, help: "Specify an OpenAI model (e.g. gpt-4, gpt-3.5-turbo).")
    var model: String = "gpt-4o-mini"

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

    func run() async throws {
        // Discover Swift files and build the lint context.
        let walker = FileWalker()
        let context: LintContext
        do {
            context = try walker.walk(root: path)
        } catch {
            throw ValidationError("Failed to walk directory: \(error.localizedDescription)")
        }
        // Build rule list.
        var selectedRules: [Rule] = []
        let allRules: [Rule] = [
            GodTypeRule(),
            DependencyInjectionSmellRule(),
            AsyncLifecycleRule()
        ]
        if let rulesCSV = rules {
            let ids = Set(rulesCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            selectedRules = allRules.filter { ids.contains($0.id) }
        } else {
            selectedRules = allRules
        }
        // Run linter.
        let linter = Linter(rules: selectedRules)
        let findings = try linter.run(context: context)
        // Build report.
        var output: String
        switch format.lowercased() {
        case "json":
            let reporter = JSONReporter()
            output = try reporter.report(findings: findings)
        default:
            // Markdown with or without inline AI explanations.
            let reporter = MarkdownReporter()
            var inlineAI: [Int: String] = [:]
            if !noAI {
                // Build iOS-focused prompts per finding and render responses inline.
                let provider = OpenAIProvider(model: model)
                let projectName = URL(fileURLWithPath: path).lastPathComponent
                for (index, finding) in findings.enumerated() {
                    let prompt = Prompt.explainFinding(
                        finding: finding,
                        projectName: projectName,
                        findingNumber: index + 1,
                        totalFindings: findings.count
                    )
                    do {
                        let aiReport = try await provider.generateMarkdown(prompt: prompt)
                        inlineAI[index] = aiReport
                    } catch {
                        inlineAI[index] = "### Root Cause\nUnable to retrieve AI analysis.\n\n### Recommended Split Boundaries\n- Derive groups from function prefixes (setup*/bind*/fetch*/handle*/validate*) and // MARK: sections in evidence.\n\n### Refactoring Steps\n- Retry with network/API key configured.\n\n### Risk & Verification Checklist\n- Run Instruments Leaks while entering/exiting the screen.\n- Repeat push/pop or present/dismiss navigation flow.\n- Verify async teardown (deinit/task cancellation).\n- Verify UI updates occur on main thread.\n- Error: \(error.localizedDescription)"
                    }
                }
            }
            output = reporter.report(findings: findings, swiftFileCount: context.swiftFiles.count, inlineAI: inlineAI)
        }
        // Write or print output.
        if let outFile = out {
            let url = URL(fileURLWithPath: outFile)
            try output.write(to: url, atomically: true, encoding: .utf8)
        } else {
            print(output)
        }

        if annotations == .github {
            GitHubAnnotationsEmitter(projectRoot: path).emit(findings: findings)
        }

        if let threshold = failOn.threshold {
            let shouldFail = findings.contains { $0.severity >= threshold }
            if shouldFail {
                throw ExitCode.failure
            }
        }
    }
}
