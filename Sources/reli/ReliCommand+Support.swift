import Foundation
import ReliCore
import ArgumentParser

/// Helper utilities extracted from `ReliCommand` to keep the command flow
/// readable and focused on orchestration.
extension ReliCommand {
    func resolveEffectiveOptions(
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default
    ) throws -> EffectiveOptions {
        let configPath = try ReliConfigLoader.discoverPath(
            explicitPath: config,
            currentDirectory: currentDirectory,
            fileManager: fileManager
        )
        let configValues = try configPath.map { try ReliConfigLoader.load(path: $0) }

        let resolvedPath = ReliConfigLoader.standardizedPath(
            path ?? configValues?.path ?? currentDirectory,
            currentDirectory: currentDirectory
        )
        let resolvedNoAI = noAI || (configValues?.noAI ?? false)
        let resolvedAILimit = aiLimit ?? configValues?.aiLimit ?? 5
        let resolvedModel = model ?? configValues?.model ?? "gpt-4o-mini"
        let resolvedFormat = (format ?? configValues?.format ?? "markdown")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedFailOn = try resolveFailOn(configValue: configValues?.failOn)
        let resolvedAnnotations = try resolveAnnotations(configValue: configValues?.annotations)
        let resolvedPathStyle = try resolvePathStyle(configValue: configValues?.pathStyle)
        let resolvedIncludeExtensions = includeExtensions ?? configValues?.includeExtensions ?? false
        let resolvedIncludeTests = includeTests || (configValues?.includeTests ?? false)
        let resolvedIncludeSamples = includeSamples || (configValues?.includeSamples ?? false)
        let resolvedRules = try resolveRules(configValue: configValues?.rules)
        let resolvedMaxFindings = maxFindings ?? configValues?.maxFindings
        let resolvedOut = out ?? configValues?.out

        let configExcludePaths = configValues?.excludePaths ?? []
        let cliExcludePaths = parseCSVList(excludePaths)
        let cliIgnorePaths = parseCSVList(ignorePaths)
        let mergedUserExcludePaths = (cliExcludePaths.isEmpty ? configExcludePaths : cliExcludePaths) + cliIgnorePaths

        var excludedPathPatterns = defaultExcludedPathPatterns(
            includeTests: resolvedIncludeTests,
            includeSamples: resolvedIncludeSamples
        )
        excludedPathPatterns.append(contentsOf: mergedUserExcludePaths)
        excludedPathPatterns = unique(excludedPathPatterns)

        guard resolvedFormat == "markdown" || resolvedFormat == "json" else {
            throw ValidationError("Invalid format value '\(resolvedFormat)'. Use markdown or json.")
        }

        return EffectiveOptions(
            path: resolvedPath,
            noAI: resolvedNoAI,
            aiLimit: resolvedAILimit,
            model: resolvedModel,
            failOn: resolvedFailOn,
            annotations: resolvedAnnotations,
            format: resolvedFormat,
            out: resolvedOut,
            rules: resolvedRules,
            includeExtensions: resolvedIncludeExtensions,
            includeTests: resolvedIncludeTests,
            includeSamples: resolvedIncludeSamples,
            excludePaths: excludedPathPatterns,
            maxFindings: resolvedMaxFindings,
            pathStyle: resolvedPathStyle,
            configPath: configPath
        )
    }

    func printEffectiveConfig(_ options: EffectiveOptions) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(options)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ValidationError("Unable to encode effective config.")
        }
        print(json)
    }

    /// Caps output findings while preserving existing ordering.
    func applyMaxFindings(to findings: [Finding], maxFindings: Int?) -> [Finding] {
        guard let maxFindings else { return findings }
        return Array(findings.prefix(maxFindings))
    }

    /// Sorts findings by severity first, then stable path/line/title ordering.
    func prioritize(_ findings: [Finding]) -> [Finding] {
        findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            let lhsLine = lhs.line ?? Int.max
            let rhsLine = rhs.line ?? Int.max
            if lhsLine != rhsLine { return lhsLine < rhsLine }
            return lhs.title < rhs.title
        }
    }

    /// Rewrites finding file paths according to the selected path style.
    func applyPathStyle(to findings: [Finding], rootPath: String, pathStyle: PathStyle) -> [Finding] {
        findings.map { finding in
            let renderedPath: String
            switch pathStyle {
            case .absolute:
                renderedPath = URL(fileURLWithPath: finding.filePath).standardizedFileURL.path
            case .relative:
                renderedPath = makeRelativePath(finding.filePath, rootPath: rootPath)
            }
            return Finding(
                ruleID: finding.ruleID,
                title: finding.title,
                message: finding.message,
                severity: finding.severity,
                filePath: renderedPath,
                line: finding.line,
                column: finding.column,
                typeName: finding.typeName,
                evidence: finding.evidence,
                snippet: finding.snippet
            )
        }
    }

    /// Converts an absolute path to a root-relative path when possible.
    func makeRelativePath(_ filePath: String, rootPath: String) -> String {
        let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let standardizedFile = URL(fileURLWithPath: filePath).standardizedFileURL.path
        if standardizedFile.hasPrefix(standardizedRoot + "/") {
            return String(standardizedFile.dropFirst(standardizedRoot.count + 1))
        }
        return filePath
    }

    /// Parses comma-separated input into a set.
    func parseCSVSet(_ csv: String?) -> Set<String> {
        Set(parseCSVList(csv))
    }

    /// Parses comma-separated input into a trimmed list.
    func parseCSVList(_ csv: String?) -> [String] {
        guard let csv, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Default path exclusions used to suppress test/sample noise unless
    /// explicitly included by CLI flags.
    func defaultExcludedPathPatterns(includeTests: Bool, includeSamples: Bool) -> [String] {
        var patterns: [String] = []
        if !includeTests {
            patterns.append(contentsOf: [
                "*Tests*/**",
                "Tests/**",
                "**/*Tests*/**",
                "**/Tests/**"
            ])
        }
        if !includeSamples {
            patterns.append(contentsOf: [
                "*Sample*/**",
                "**/*Sample*/**",
                "Examples/**",
                "*/Examples/**",
                "**/Examples/**"
            ])
        }
        return patterns
    }

    func resolveRules(configValue: ConfigRulesValue?) throws -> RulesSelection {
        if let rules {
            let parsed = rules
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parsed.count == 1, parsed[0].caseInsensitiveCompare("all") == .orderedSame {
                return .all
            }
            guard !parsed.isEmpty else {
                throw ValidationError("Invalid --rules value. Provide comma-separated rule IDs or all.")
            }
            return .list(unique(parsed))
        }

        if let configValue {
            let resolved = configValue.toRulesSelection()
            if case .list(let ids) = resolved, ids.isEmpty {
                throw ValidationError("Invalid config file: rules must be \"all\" or a non-empty list.")
            }
            return resolved
        }

        return .all
    }

    func resolveFailOn(configValue: String?) throws -> FailOn {
        if let failOn {
            return failOn
        }
        guard let configValue = configValue?.trimmingCharacters(in: .whitespacesAndNewlines), !configValue.isEmpty else {
            return .off
        }
        guard let parsed = FailOn(rawValue: configValue.lowercased()) else {
            throw ValidationError("Invalid config file: failOn must be one of off, low, medium, high.")
        }
        return parsed
    }

    func resolveAnnotations(configValue: String?) throws -> AnnotationsMode {
        if let annotations {
            return annotations
        }
        guard let configValue = configValue?.trimmingCharacters(in: .whitespacesAndNewlines), !configValue.isEmpty else {
            return .off
        }
        guard let parsed = AnnotationsMode(rawValue: configValue.lowercased()) else {
            throw ValidationError("Invalid config file: annotations must be one of off, github.")
        }
        return parsed
    }

    func resolvePathStyle(configValue: String?) throws -> PathStyle {
        if let pathStyle {
            return pathStyle
        }
        guard let configValue = configValue?.trimmingCharacters(in: .whitespacesAndNewlines), !configValue.isEmpty else {
            return .relative
        }
        guard let parsed = PathStyle(rawValue: configValue.lowercased()) else {
            throw ValidationError("Invalid config file: pathStyle must be one of relative, absolute.")
        }
        return parsed
    }

    func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            ordered.append(value)
        }
        return ordered
    }
}
