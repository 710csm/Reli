import Foundation
import ReliCore
import ReliRules
import ArgumentParser

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
    var model: String = "gpt-4"

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
            // Markdown with or without AI explanations.
            let reporter = MarkdownReporter()
            var report = reporter.report(findings: findings)
            if !noAI {
                // Build AI prompt and invoke provider.
                let prompt = Prompt.explain(findings: findings, projectName: URL(fileURLWithPath: path).lastPathComponent)
                let provider = OpenAIProvider(model: model)
                do {
                    let aiReport = try await provider.generateMarkdown(prompt: prompt)
                    report += "\n\n## AI Recommendations\n\n" + aiReport
                } catch {
                    // If AI invocation fails, append a message but still return the raw report.
                    report += "\n\n*Note: Failed to retrieve AI recommendations: \(error.localizedDescription)*"
                }
            }
            output = report
        }
        // Write or print output.
        if let outFile = out {
            let url = URL(fileURLWithPath: outFile)
            try output.write(to: url, atomically: true, encoding: .utf8)
        } else {
            print(output)
        }
        
        print("Total swift files:", context.swiftFiles.count)
        print("Total findings:", findings.count)
    }
}
