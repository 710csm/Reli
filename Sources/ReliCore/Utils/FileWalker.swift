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
    /// - Parameter excludedPathPatterns: Glob-like patterns matched against
    ///   root-relative file paths (`*`, `**`, `?` supported).
    /// - Returns: A `LintContext` representing the discovered files.
    public func walk(root: String, excludedPathPatterns: [String] = []) throws -> LintContext {
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
                let normalizedRelativePath = path.replacingOccurrences(of: "\\", with: "/")
                if matchesAnyPattern(normalizedRelativePath, patterns: excludedPathPatterns) {
                    continue
                }
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

    private func matchesAnyPattern(_ path: String, patterns: [String]) -> Bool {
        patterns.contains { globMatch(path, pattern: $0) }
    }

    private func globMatch(_ path: String, pattern: String) -> Bool {
        var p = pattern.replacingOccurrences(of: "\\", with: "/")
        if p.hasPrefix("/") {
            p = String(p.dropFirst())
        }
        if p.hasPrefix("./") {
            p = String(p.dropFirst(2))
        }

        var regex = "^"
        var idx = p.startIndex
        while idx < p.endIndex {
            let ch = p[idx]
            if ch == "*" {
                let next = p.index(after: idx)
                if next < p.endIndex, p[next] == "*" {
                    regex += ".*"
                    idx = p.index(after: next)
                } else {
                    regex += "[^/]*"
                    idx = next
                }
                continue
            }
            if ch == "?" {
                regex += "[^/]"
                idx = p.index(after: idx)
                continue
            }
            if ".+()[]{}|^$\\".contains(ch) {
                regex += "\\"
            }
            regex.append(ch)
            idx = p.index(after: idx)
        }
        regex += "$"

        guard let re = try? NSRegularExpression(pattern: regex, options: []) else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return re.firstMatch(in: path, options: [], range: range) != nil
    }
}
