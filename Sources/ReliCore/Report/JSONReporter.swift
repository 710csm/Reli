import Foundation

/// Emits lint findings in JSON format. Useful for integration with other
/// tools or for machine consumption. Encodes the findings array directly
/// using `JSONEncoder`.
public struct JSONReporter {
    
    public init() { }
    
    /// Serialises the given findings to a JSON string. Any encoding errors
    /// will cause a thrown exception; callers should handle errors.
    ///
    /// - Parameter findings: The findings to encode.
    /// - Returns: A JSON string representing the findings array.
    public func report(findings: [Finding]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(findings)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JSONReporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON"])
        }
        return jsonString
    }
}
