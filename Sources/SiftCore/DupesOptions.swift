//
// Copyright © Agulhas Labs
//

/// `dupes`'s own options: the overlap floor a pair has to reach, the page of groups to show, and what becomes of test and preview code.
public struct DupesOptions: Sendable, Equatable {
    /// The shared-callee overlap every pair in a group reaches, `SimilarityScore.dupesFloor` unless the caller raised or lowered it.
    public var minimumOverlap: Double
    /// Groups skipped before the page starts — the cursor a `truncated:` marker names.
    public var offset: Int
    public var testCode: TestCode
    /// The declarations a comparison follows: nil compares every candidate pair, a set proposes only pairs with a seed on one side, and a seed that is test or preview code is not one.
    public var seeds: Set<DupesSeedKey>?

    /// A nil `minimumOverlap` is the default floor.
    public init(minimumOverlap: Double? = nil, offset: Int = 0, testCode: TestCode = .rankedLast, seeds: Set<DupesSeedKey>? = nil) {
        self.minimumOverlap = minimumOverlap ?? SimilarityScore.dupesFloor
        self.offset = max(0, offset)
        self.testCode = testCode
        self.seeds = seeds
    }
}

public extension DupesOptions {
    /// What the audit does with test and preview code, as `DupesRanking.isTestOrPreview` reads it.
    enum TestCode: Sendable, Equatable {
        /// Grouped as usual, but a group made only of it is listed after every other group.
        case rankedLast
        /// Ranked with the rest, as any other group.
        case rankedWithTheRest
        /// Left out of the comparison altogether, and counted.
        case leftOut
    }
}
