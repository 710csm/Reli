import Testing
import ReliCore

@Test func aiLimitDefaultsToTopFive() {
    let indices = AILimitSelector.selectedIndices(totalFindings: 12, limit: 5)
    #expect(indices == [0, 1, 2, 3, 4])
}

@Test func aiLimitAllowsZero() {
    let indices = AILimitSelector.selectedIndices(totalFindings: 12, limit: 0)
    #expect(indices.isEmpty)
}

@Test func aiLimitHandlesLimitAboveFindingCount() {
    let indices = AILimitSelector.selectedIndices(totalFindings: 7, limit: 10)
    #expect(indices == [0, 1, 2, 3, 4, 5, 6])
}

@Test func aiLimitHandlesNegativeSafely() {
    let indices = AILimitSelector.selectedIndices(totalFindings: 7, limit: -1)
    #expect(indices.isEmpty)
}
