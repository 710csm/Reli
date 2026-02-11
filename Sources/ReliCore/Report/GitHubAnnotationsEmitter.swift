import Foundation

/// Emits lint findings as GitHub Actions workflow command annotations.
public struct GitHubAnnotationsEmitter {
    private let projectRoot: String

    public init(projectRoot: String) {
        self.projectRoot = URL(fileURLWithPath: projectRoot).standardizedFileURL.path
    }

    public func emit(findings: [Finding]) {
        for finding in findings {
            // Keep annotation noise manageable in PRs.
            guard finding.severity >= .medium else { continue }
            guard let line = finding.line else { continue }

            let level = mapLevel(finding.severity)
            let file = escapeProperty(relativePath(for: finding.filePath))
            let title = escapeProperty(finding.title)
            let message = escapeMessage(finding.message)

            if let column = finding.column {
                print("::\(level) file=\(file),line=\(line),col=\(column),title=\(title)::\(message)")
            } else {
                print("::\(level) file=\(file),line=\(line),title=\(title)::\(message)")
            }
        }
    }

    private func mapLevel(_ severity: Severity) -> String {
        switch severity {
        case .high:
            return "error"
        case .medium:
            return "warning"
        case .low, .info:
            return "notice"
        }
    }

    private func relativePath(for filePath: String) -> String {
        let standardizedFile = URL(fileURLWithPath: filePath).standardizedFileURL.path
        if standardizedFile.hasPrefix(projectRoot + "/") {
            return String(standardizedFile.dropFirst(projectRoot.count + 1))
        }
        if standardizedFile == projectRoot {
            return standardizedFile
        }
        if filePath.hasPrefix("./") {
            return String(filePath.dropFirst(2))
        }
        return filePath
    }

    private func escapeMessage(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    private func escapeProperty(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: ",", with: "%2C")
    }
}
