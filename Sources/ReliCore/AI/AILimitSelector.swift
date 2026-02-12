/// Pure helper for selecting which findings should be sent to AI.
/// The command layer owns validation; this type only applies bounds safely.
public enum AILimitSelector {
    /// Returns finding indices `[0..<N]` where `N = min(totalFindings, limit)`.
    /// Non-positive limits yield an empty selection.
    public static func selectedIndices(totalFindings: Int, limit: Int) -> [Int] {
        guard totalFindings > 0, limit > 0 else { return [] }
        return Array(0..<min(totalFindings, limit))
    }
}
