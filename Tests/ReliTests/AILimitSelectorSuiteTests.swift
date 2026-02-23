import Testing
import ReliCore

@Suite("AI Limit Selector")
struct AILimitSelectorSuite {
    @Test func selectsTopNIndices() {
        let indices = AILimitSelector.selectedIndices(totalFindings: 12, limit: 5)
        #expect(indices == [0, 1, 2, 3, 4])
    }

    @Test func returnsEmptyForZeroOrNegativeLimit() {
        let zero = AILimitSelector.selectedIndices(totalFindings: 12, limit: 0)
        let negative = AILimitSelector.selectedIndices(totalFindings: 7, limit: -1)
        #expect(zero.isEmpty)
        #expect(negative.isEmpty)
    }

    @Test func capsAtAvailableFindings() {
        let indices = AILimitSelector.selectedIndices(totalFindings: 3, limit: 10)
        #expect(indices == [0, 1, 2])
    }
}
