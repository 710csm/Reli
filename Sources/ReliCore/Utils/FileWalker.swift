import Foundation

/// Utility responsible for traversing directories and collecting Swift source
/// files. The walker ignores hidden directories and certain common build
/// directories such as `.build` and `DerivedData`. You can customise the
/// ignore list by modifying the `ignoredDirectoryNames` constant.
public struct FileWalker {
    
    public init() {}
    
    /// Directories that should be skipped when scanning for Swift files.
    private let ignoredDirectoryNames: Set<String> = [".git", ".build", "DerivedData"]

    /// Recursively collects all `.swift` files under the given root path and
    /// loads their contents. Returns a `LintContext` containing the results.
    ///
    /// - Parameter root: The directory to scan.
    /// - Returns: A `LintContext` representing the discovered files.
    public func walk(root: String) throws -> LintContext {
        var swiftFiles: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else {
            return LintContext(rootPath: root, swiftFiles: [], fileContents: [:])
        }
        for case let path as String in enumerator {
            let components = path.split(separator: "/")
            if let dir = components.first, ignoredDirectoryNames.contains(String(dir)) {
                enumerator.skipDescendants()
                continue
            }
            if path.hasSuffix(".swift") {
                swiftFiles.append((root as NSString).appendingPathComponent(path))
            }
        }
        var contents: [String: String] = [:]
        for file in swiftFiles {
            print("Found swift file:", file)
            do {
                contents[file] = try String(contentsOfFile: file, encoding: .utf8)
            } catch {
                contents[file] = ""
            }
        }
        return LintContext(rootPath: root, swiftFiles: swiftFiles, fileContents: contents)
    }
}
