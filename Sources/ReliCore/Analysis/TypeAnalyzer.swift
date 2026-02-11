import Foundation
import SwiftParser
import SwiftSyntax

public struct TypeFunctionMetric: Sendable {
    public let name: String
    public let startLine: Int
    public let endLine: Int

    public var lineSpan: Int {
        max(1, endLine - startLine + 1)
    }
}

public struct TypeAnalysis: Sendable {
    public let name: String
    public let kind: String
    public let startLine: Int
    public let lineCount: Int
    public let functions: [TypeFunctionMetric]
    public let extensionCount: Int
    public let uiActionCount: Int
    public let markSections: [String]
}

public struct TypeAnalyzer {
    public init() {}

    public func analyze(filePath: String, source: String, includeExtensions: Bool) -> [TypeAnalysis] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: tree)
        let collector = TypeCollector(
            source: source,
            converter: converter,
            includeExtensions: includeExtensions
        )
        collector.walk(tree)
        return collector.analyses()
    }
}

private final class TypeCollector: SyntaxVisitor {
    private let source: String
    private let converter: SourceLocationConverter
    private let includeExtensions: Bool

    private var typeOrder: [String] = []
    private var typeInfosByName: [String: MutableTypeInfo] = [:]
    private var pendingExtensionsByType: [String: [ExtensionMetrics]] = [:]

    init(source: String, converter: SourceLocationConverter, includeExtensions: Bool) {
        self.source = source
        self.converter = converter
        self.includeExtensions = includeExtensions
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(name: node.name.text, node: node, kind: "class")
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(name: node.name.text, node: node, kind: "struct")
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(name: node.name.text, node: node, kind: "enum")
        return .skipChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(name: node.name.text, node: node, kind: "actor")
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard includeExtensions else { return .skipChildren }
        let typeName = normalizedTypeName(node.extendedType.description)
        guard !typeName.isEmpty else { return .skipChildren }

        let metrics = analyzeExtension(node)
        if var base = typeInfosByName[typeName] {
            base.lineCount += metrics.lineCount
            base.extensionCount += 1
            base.uiActionCount += metrics.uiActionCount
            base.functions.append(contentsOf: metrics.functions)
            base.markSections.append(contentsOf: metrics.markSections)
            typeInfosByName[typeName] = base
        } else {
            pendingExtensionsByType[typeName, default: []].append(metrics)
        }
        return .skipChildren
    }

    func analyses() -> [TypeAnalysis] {
        var merged = typeInfosByName
        if includeExtensions {
            for (typeName, extMetrics) in pendingExtensionsByType {
                if var base = merged[typeName] {
                    for ext in extMetrics {
                        base.lineCount += ext.lineCount
                        base.extensionCount += 1
                        base.uiActionCount += ext.uiActionCount
                        base.functions.append(contentsOf: ext.functions)
                        base.markSections.append(contentsOf: ext.markSections)
                    }
                    merged[typeName] = base
                } else {
                    let sorted = extMetrics.sorted { $0.startLine < $1.startLine }
                    let lineCount = sorted.reduce(0) { $0 + $1.lineCount }
                    let uiActionCount = sorted.reduce(0) { $0 + $1.uiActionCount }
                    let functions = sorted.flatMap(\.functions)
                    let markSections = sorted.flatMap(\.markSections)
                    merged[typeName] = MutableTypeInfo(
                        name: typeName,
                        kind: "extension",
                        startLine: sorted.first?.startLine ?? 1,
                        lineCount: lineCount,
                        functions: functions,
                        extensionCount: sorted.count,
                        uiActionCount: uiActionCount,
                        markSections: markSections
                    )
                    if !typeOrder.contains(typeName) {
                        typeOrder.append(typeName)
                    }
                }
            }
        }

        return typeOrder.compactMap { name in
            guard let info = merged[name] else { return nil }
            let sortedFunctions = info.functions.sorted { lhs, rhs in
                if lhs.startLine == rhs.startLine { return lhs.name < rhs.name }
                return lhs.startLine < rhs.startLine
            }
            return TypeAnalysis(
                name: info.name,
                kind: info.kind,
                startLine: info.startLine,
                lineCount: info.lineCount,
                functions: sortedFunctions,
                extensionCount: info.extensionCount,
                uiActionCount: info.uiActionCount,
                markSections: info.markSections
            )
        }
    }

    private func registerType<T: DeclGroupSyntax & SyntaxProtocol>(name: String, node: T, kind: String) {
        let sourceText = node.description
        let functions = functionsFrom(memberBlock: node.memberBlock)
        let lineInfo = lineInfo(of: node)
        let markSections = parseMarkSections(from: sourceText)
        let uiActionCount = countUIActions(in: sourceText) + countIBActionAttributes(in: functions)
        var info = MutableTypeInfo(
            name: name,
            kind: kind,
            startLine: lineInfo.startLine,
            lineCount: lineInfo.lineCount,
            functions: functions,
            extensionCount: 0,
            uiActionCount: uiActionCount,
            markSections: markSections
        )
        if includeExtensions, let pending = pendingExtensionsByType.removeValue(forKey: name) {
            for ext in pending {
                info.lineCount += ext.lineCount
                info.extensionCount += 1
                info.uiActionCount += ext.uiActionCount
                info.functions.append(contentsOf: ext.functions)
                info.markSections.append(contentsOf: ext.markSections)
            }
        }

        if typeInfosByName[name] == nil {
            typeOrder.append(name)
            typeInfosByName[name] = info
        } else {
            // Merge duplicate declarations conservatively.
            var existing = typeInfosByName[name]!
            existing.lineCount += info.lineCount
            existing.functions.append(contentsOf: info.functions)
            existing.uiActionCount += info.uiActionCount
            existing.markSections.append(contentsOf: info.markSections)
            typeInfosByName[name] = existing
        }
    }

    private func analyzeExtension(_ node: ExtensionDeclSyntax) -> ExtensionMetrics {
        let sourceText = node.description
        let lineInfo = lineInfo(of: node)
        let functions = functionsFrom(memberBlock: node.memberBlock)
        let markSections = parseMarkSections(from: sourceText)
        let uiActionCount = countUIActions(in: sourceText) + countIBActionAttributes(in: functions)
        return ExtensionMetrics(
            startLine: lineInfo.startLine,
            lineCount: lineInfo.lineCount,
            functions: functions,
            uiActionCount: uiActionCount,
            markSections: markSections
        )
    }

    private func functionsFrom(memberBlock: MemberBlockSyntax) -> [TypeFunctionMetric] {
        memberBlock.members.compactMap { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            let start = lineNumber(of: function.positionAfterSkippingLeadingTrivia)
            let end = lineNumber(of: function.endPositionBeforeTrailingTrivia)
            return TypeFunctionMetric(name: function.name.text, startLine: start, endLine: end)
        }
    }

    private func lineInfo<T: SyntaxProtocol>(of node: T) -> (startLine: Int, lineCount: Int) {
        let start = lineNumber(of: node.positionAfterSkippingLeadingTrivia)
        let end = lineNumber(of: node.endPositionBeforeTrailingTrivia)
        return (start, max(1, end - start + 1))
    }

    private func lineNumber(of position: AbsolutePosition) -> Int {
        converter.location(for: position).line
    }

    private func parseMarkSections(from text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("// MARK:") else { return nil }
                let section = line.replacingOccurrences(of: "// MARK:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return section.isEmpty ? "-" : section
            }
    }

    private func countUIActions(in text: String) -> Int {
        text.components(separatedBy: ".addTarget(").count - 1
    }

    private func countIBActionAttributes(in functions: [TypeFunctionMetric]) -> Int {
        // Attribute-level detection is approximate; this uses source slice checks.
        // We intentionally avoid regex function counting for v0.2.
        var count = 0
        for fn in functions {
            if sourceContainsIBAction(around: fn.startLine, endLine: fn.endLine) {
                count += 1
            }
        }
        return count
    }

    private func sourceContainsIBAction(around startLine: Int, endLine: Int) -> Bool {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return false }
        let from = max(1, startLine - 1)
        let to = min(lines.count, max(startLine, endLine))
        guard from <= to else { return false }
        let chunk = lines[(from - 1)...(to - 1)].joined(separator: "\n")
        return chunk.contains("@IBAction")
    }

    private func normalizedTypeName(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let genericIndex = text.firstIndex(of: "<") {
            text = String(text[..<genericIndex])
        }
        if let dotIndex = text.lastIndex(of: ".") {
            text = String(text[text.index(after: dotIndex)...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct MutableTypeInfo {
        var name: String
        var kind: String
        var startLine: Int
        var lineCount: Int
        var functions: [TypeFunctionMetric]
        var extensionCount: Int
        var uiActionCount: Int
        var markSections: [String]
    }

    private struct ExtensionMetrics {
        let startLine: Int
        let lineCount: Int
        let functions: [TypeFunctionMetric]
        let uiActionCount: Int
        let markSections: [String]
    }
}
