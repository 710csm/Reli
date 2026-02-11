import Foundation

/// Protocol for AI providers capable of generating Markdown explanations
/// for lint findings. Implementations should make network calls to the
/// underlying AI service and return a complete Markdown report. Errors
/// thrown by the provider should be propagated.
public protocol AIClient: Sendable {
    /// Generates a Markdown document given a prompt. The prompt should
    /// include all necessary context and instructions for the AI. The
    /// returned Markdown will be appended to the main report by the CLI.
    func generateMarkdown(prompt: String) async throws -> String
}
