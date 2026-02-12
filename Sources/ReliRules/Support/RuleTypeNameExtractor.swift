import Foundation

enum RuleTypeNameExtractor {
    static func extractRelevantTypeNames(from text: String) -> [String] {
        let declarationPattern = try! NSRegularExpression(
            pattern: "\\b(?:final\\s+)?(?:public\\s+|internal\\s+|private\\s+|fileprivate\\s+|open\\s+)?(?:class|struct|actor)\\s+([A-Z][A-Za-z0-9_]*)",
            options: []
        )
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = declarationPattern.matches(in: text, options: [], range: range)

        var allNames: [String] = []
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            if !allNames.contains(name) {
                allNames.append(name)
            }
        }

        let targetSuffixes = ["ViewController", "VC", "ViewModel", "VM"]
        let focused = allNames.filter { name in
            targetSuffixes.contains { name.hasSuffix($0) }
        }
        return focused.isEmpty ? allNames : focused
    }
}
