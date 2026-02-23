import Testing
import ReliCore

@Suite("Markdown Reporter")
struct MarkdownReporterSuite {
    @Test func includesAISummaryLines() {
        let reporter = MarkdownReporter()
        let markdown = reporter.report(
            findings: [TestUtils.makeFinding(title: "F1", severity: .medium)],
            swiftFileCount: 10,
            inlineAI: [:],
            totalFindings: 12,
            aiStatus: "disabled (--no-ai)",
            aiCallLimit: 5,
            aiPlannedCalls: 0
        )

        #expect(markdown.contains("- AI: disabled (--no-ai)"))
        #expect(markdown.contains("- AI call limit: up to 5 findings per run (`--ai-limit`, default: 5)"))
        #expect(markdown.contains("- AI planned calls this run: 0"))
        #expect(markdown.contains("- Total findings: 12"))
    }

    @Test func printsInlineAIOnlyForMappedIndex() {
        let reporter = MarkdownReporter()
        let findings = [
            TestUtils.makeFinding(title: "F1", severity: .high),
            TestUtils.makeFinding(title: "F2", severity: .low)
        ]

        let markdown = reporter.report(
            findings: findings,
            swiftFileCount: 2,
            inlineAI: [0: "### Root Cause\nFirst finding only"],
            totalFindings: 2,
            aiStatus: nil,
            aiCallLimit: 1,
            aiPlannedCalls: 1
        )

        #expect(markdown.contains("#### Finding 1: F1"))
        #expect(markdown.contains("#### Finding 2: F2"))
        #expect(markdown.contains("First finding only"))
        let aiAnalysisCount = markdown.components(separatedBy: "- AI Analysis:").count - 1
        #expect(aiAnalysisCount == 1)
    }

    @Test func showsHighestSeverityFirst() {
        let reporter = MarkdownReporter()
        let findings = [
            TestUtils.makeFinding(title: "LowFinding", severity: .low),
            TestUtils.makeFinding(title: "HighFinding", severity: .high)
        ]
        let markdown = reporter.report(
            findings: findings,
            swiftFileCount: 2,
            inlineAI: [:]
        )

        let highIndex = markdown.range(of: "### High")
        let lowIndex = markdown.range(of: "### Low")
        #expect(highIndex != nil)
        #expect(lowIndex != nil)
        if let highIndex, let lowIndex {
            #expect(highIndex.lowerBound < lowIndex.lowerBound)
        }
    }
}
