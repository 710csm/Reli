import Testing
import Foundation
import ReliCore
@testable import reli

@Suite("Reli Command Integration")
struct ReliCommandIntegrationSuite {
    @Test func keepsExistingDefaultsWithoutConfig() throws {
        try TestUtils.withTemporaryDirectory { tempDir in
            let command = try TestUtils.parseReliCommand([])
            let options = try command.resolveEffectiveOptions(currentDirectory: tempDir.path)

            #expect(options.aiLimit == 5)
            #expect(options.format == "markdown")
            #expect(options.model == "gpt-4o-mini")
            #expect(options.failOn == .off)
            #expect(options.annotations == .off)
            #expect(options.includeTests == false)
            #expect(options.includeSamples == false)
            #expect(options.configPath == nil)
        }
    }

    @Test func autoLoadsDotReliYml() throws {
        try TestUtils.withTemporaryDirectory { tempDir in
            let configPath = tempDir.appendingPathComponent(".reli.yml")
            try """
            aiLimit: 7
            includeTests: true
            rules: all
            """.write(to: configPath, atomically: true, encoding: .utf8)

            let command = try TestUtils.parseReliCommand([])
            let options = try command.resolveEffectiveOptions(currentDirectory: tempDir.path)

            #expect(options.aiLimit == 7)
            #expect(options.includeTests == true)
            #expect(options.configPath == configPath.path)
        }
    }

    @Test func explicitConfigMustExist() async throws {
        let command = try TestUtils.parseReliCommand([
            "--config", "/tmp/does-not-exist.reli.yml"
        ])

        do {
            try await command.run()
            Issue.record("Expected run() to fail for missing --config file.")
        } catch {
            #expect(String(describing: error).contains("Config file not found"))
        }
    }

    @Test func cliOverridesConfigValues() throws {
        try TestUtils.withTemporaryDirectory { tempDir in
            let configPath = tempDir.appendingPathComponent(".reli.yml")
            try """
            aiLimit: 5
            includeExtensions: false
            format: markdown
            """.write(to: configPath, atomically: true, encoding: .utf8)

            let command = try TestUtils.parseReliCommand([
                "--config", configPath.path,
                "--ai-limit", "2",
                "--include-extensions", "true",
                "--format", "json"
            ])
            let options = try command.resolveEffectiveOptions(currentDirectory: tempDir.path)

            #expect(options.aiLimit == 2)
            #expect(options.includeExtensions == true)
            #expect(options.format == "json")
        }
    }

    @Test func printConfigOutputsFinalMergedValues() async throws {
        try await TestUtils.withTemporaryDirectory { tempDir in
            let configPath = tempDir.appendingPathComponent(".reli.yml")
            try """
            aiLimit: 9
            failOn: medium
            rules:
              - god-type
            """.write(to: configPath, atomically: true, encoding: .utf8)

            let command = try TestUtils.parseReliCommand([
                "--config", configPath.path,
                "--ai-limit", "2",
                "--print-config"
            ])

            let output = try await TestUtils.captureStdout {
                try await command.run()
            }
            let start = try #require(output.firstIndex(of: "{"))
            let end = try #require(output.lastIndex(of: "}"))
            let jsonText = String(output[start...end])
            let data = try #require(jsonText.data(using: .utf8))
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let aiLimit = object?["aiLimit"] as? Int
            let failOn = object?["failOn"] as? String

            #expect(aiLimit == 2)
            #expect(failOn == "medium")
        }
    }

    @Test func appliesExcludeAndIncludeOptionsAtFileCollectionStage() throws {
        try TestUtils.withTemporaryDirectory { tempDir in
            let sourceDir = tempDir.appendingPathComponent("Sources")
            let testsDir = tempDir.appendingPathComponent("Tests")
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)

            try "final class Prod {}".write(
                to: sourceDir.appendingPathComponent("Prod.swift"),
                atomically: true,
                encoding: .utf8
            )
            try "final class ProdTests {}".write(
                to: testsDir.appendingPathComponent("ProdTests.swift"),
                atomically: true,
                encoding: .utf8
            )

            let defaultCommand = try TestUtils.parseReliCommand(["--path", tempDir.path])
            let defaultOptions = try defaultCommand.resolveEffectiveOptions(currentDirectory: tempDir.path)
            let includedOnlyProd = try FileWalker().walk(root: tempDir.path, excludedPathPatterns: defaultOptions.excludePaths)
            #expect(includedOnlyProd.swiftFiles.count == 1)

            let includeTestsCommand = try TestUtils.parseReliCommand([
                "--path", tempDir.path,
                "--include-tests"
            ])
            let includeTestsOptions = try includeTestsCommand.resolveEffectiveOptions(currentDirectory: tempDir.path)
            let includedProdAndTests = try FileWalker().walk(root: tempDir.path, excludedPathPatterns: includeTestsOptions.excludePaths)
            #expect(includedProdAndTests.swiftFiles.count == 2)
        }
    }
}
