import Foundation
import ArgumentParser
import Yams

enum RulesSelection: Encodable {
    case all
    case list([String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all:
            try container.encode("all")
        case .list(let ids):
            try container.encode(ids)
        }
    }
}

struct ReliConfig: Decodable {
    var path: String?
    var noAI: Bool?
    var aiLimit: Int?
    var model: String?
    var failOn: String?
    var annotations: String?
    var format: String?
    var out: String?
    var rules: ConfigRulesValue?
    var includeExtensions: Bool?
    var includeTests: Bool?
    var includeSamples: Bool?
    var excludePaths: [String]?
    var maxFindings: Int?
    var pathStyle: String?
}

enum ConfigRulesValue: Decodable {
    case all
    case list([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.caseInsensitiveCompare("all") == .orderedSame {
                self = .all
                return
            }
            let split = trimmed
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self = .list(split)
            return
        }
        if let list = try? container.decode([String].self) {
            self = .list(list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            return
        }
        throw DecodingError.typeMismatch(
            ConfigRulesValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "rules must be \"all\" or [String].")
        )
    }

    func toRulesSelection() -> RulesSelection {
        switch self {
        case .all:
            return .all
        case .list(let ids):
            if ids.count == 1, ids[0].caseInsensitiveCompare("all") == .orderedSame {
                return .all
            }
            return .list(ids)
        }
    }
}

struct EffectiveOptions: Encodable {
    var path: String
    var noAI: Bool
    var aiLimit: Int
    var model: String
    var failOn: FailOn
    var annotations: AnnotationsMode
    var format: String
    var out: String?
    var rules: RulesSelection
    var includeExtensions: Bool
    var includeTests: Bool
    var includeSamples: Bool
    var excludePaths: [String]
    var maxFindings: Int?
    var pathStyle: PathStyle
    var configPath: String?
}

enum ReliConfigLoader {
    static func discoverPath(
        explicitPath: String?,
        currentDirectory: String,
        fileManager: FileManager = .default
    ) throws -> String? {
        if let explicitPath {
            let standardized = standardizedPath(explicitPath, currentDirectory: currentDirectory)
            guard fileManager.fileExists(atPath: standardized) else {
                throw ValidationError("Config file not found: \(standardized)")
            }
            return standardized
        }

        let autoPath = URL(fileURLWithPath: currentDirectory)
            .appendingPathComponent(".reli.yml")
            .standardizedFileURL
            .path
        return fileManager.fileExists(atPath: autoPath) ? autoPath : nil
    }

    static func load(path: String) throws -> ReliConfig {
        do {
            let yamlString = try String(contentsOfFile: path, encoding: .utf8)
            let decoder = YAMLDecoder()
            return try decoder.decode(ReliConfig.self, from: yamlString)
        } catch {
            throw ValidationError("Invalid config file: \(error.localizedDescription)")
        }
    }

    static func standardizedPath(_ rawPath: String, currentDirectory: String) -> String {
        let url: URL
        if rawPath.hasPrefix("/") {
            url = URL(fileURLWithPath: rawPath)
        } else {
            url = URL(fileURLWithPath: currentDirectory).appendingPathComponent(rawPath)
        }
        return url.standardizedFileURL.path
    }
}
