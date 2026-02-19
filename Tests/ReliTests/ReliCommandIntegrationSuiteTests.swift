import Testing
import Foundation
import ReliCore
@testable import reli

@Suite("Reli Command Integration")
struct ReliCommandIntegrationSuite {
    @Test func parsesDefaultAiLimit() throws {
        let command = try TestUtils.parseReliCommand([
            "--path", "/tmp",
            "--no-ai"
        ])
        #expect(command.aiLimit == 5)
    }

    @Test func parsesCustomAiLimit() throws {
        let command = try TestUtils.parseReliCommand([
            "--path", "/tmp",
            "--no-ai",
            "--ai-limit", "3"
        ])
        #expect(command.aiLimit == 3)
    }

    @Test func runRejectsNegativeAiLimit() async throws {
        var command = try TestUtils.parseReliCommand([
            "--path", "/tmp",
            "--no-ai"
        ])
        command.aiLimit = -1

        do {
            try await command.run()
            Issue.record("Expected run() to fail for negative --ai-limit.")
        } catch {
            #expect(String(describing: error).contains("--ai-limit must be zero or a positive integer."))
        }
    }

    @Test func runRejectsInvalidMaxFindings() async throws {
        var command = try TestUtils.parseReliCommand([
            "--path", "/tmp",
            "--no-ai"
        ])
        command.maxFindings = 0

        do {
            try await command.run()
            Issue.record("Expected run() to fail for non-positive --max-findings.")
        } catch {
            #expect(String(describing: error).contains("--max-findings must be a positive integer."))
        }
    }

    @Test func runSucceedsWithNoAIOnFixtureProject() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("reli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let swiftFile = fixtureRoot.appendingPathComponent("Sample.swift")
        try "final class Sample { func run() {} }\n"
            .write(to: swiftFile, atomically: true, encoding: .utf8)

        let outFile = fixtureRoot.appendingPathComponent("report.json")
        let command = try TestUtils.parseReliCommand([
            "--path", fixtureRoot.path,
            "--no-ai",
            "--format", "json",
            "--out", outFile.path,
            "--ai-limit", "2"
        ])
        try await command.run()

        let output = try String(contentsOf: outFile, encoding: .utf8)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["))
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode([Finding].self, from: data)
        #expect(decoded.count >= 0)
    }
}
