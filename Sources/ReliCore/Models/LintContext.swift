import Foundation

/// Represents the contents of the codebase being analysed. The linter will
/// traverse the file system to locate Swift source files and load their
/// contents into memory. Additional metadata may be added in future such
/// as module graphs or dependency information to support more advanced
/// analyses.
public struct LintContext: Sendable {
    /// The root directory of the project being analysed.
    public let rootPath: String
    /// A list of absolute paths to Swift source files.
    public let swiftFiles: [String]
    /// A map from file paths to their entire contents. Loading contents
    /// into memory allows rules to operate quickly without repeatedly
    /// hitting the file system. In a large project this may be optimised
    /// using lazy loading or memory‑mapped files.
    public let fileContents: [String: String]

    public init(rootPath: String, swiftFiles: [String], fileContents: [String: String]) {
        self.rootPath = rootPath
        self.swiftFiles = swiftFiles
        self.fileContents = fileContents
    }
}
