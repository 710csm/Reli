import Foundation
import ReliCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import reli

enum TestUtils {
    static func makeFinding(title: String, severity: Severity) -> Finding {
        Finding(
            ruleID: "test-rule",
            title: title,
            message: "message",
            severity: severity,
            filePath: "Sources/Test.swift",
            line: 1
        )
    }

    static func parseReliCommand(_ arguments: [String]) throws -> ReliCommand {
        let parsed = try ReliCommand.parseAsRoot(arguments)
        guard let command = parsed as? ReliCommand else {
            throw NSError(
                domain: "ReliTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse ReliCommand."]
            )
        }
        return command
    }

    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    static func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    static func captureStdout(_ operation: () async throws -> Void) async throws -> String {
        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        fflush(stdout)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        do {
            try await operation()
            fflush(stdout)
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            pipe.fileHandleForWriting.closeFile()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            fflush(stdout)
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            pipe.fileHandleForWriting.closeFile()
            throw error
        }
    }
}
