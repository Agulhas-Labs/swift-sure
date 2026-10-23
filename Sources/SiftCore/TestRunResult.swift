//
// Copyright © Agulhas Labs
//

/// What a finished sharded run hands back: the one text to print and the one code to exit with.
///
/// The answer is already rendered here rather than left as a report for the caller to render, because every ending this run has — a refusal, a failed build, an interruption, a reconciliation — is answered in the same shape, and a front end that rendered them would be a second place that shape is decided.
public struct TestRunResult: Sendable {
    /// The whole answer, ready to print.
    public let answer: String

    /// What `swift-sure test` exits with.
    public let exitCode: Int32

    /// How the shards' reconciliation ended, where the run got as far as reconciling them; a red that SwiftSure ended for an interruption once the shards had started; `nil` for a refusal, a failed build, an empty listing or an interruption before the shards, none of which tested the tree.
    public let reconciled: Reconciled?

    /// The token every log of the run carries in its name, where the run got as far as the shards; `nil` for any other producer.
    public let runToken: String?

    /// How many shards the run planned and ran, where it got as far as the shards; `nil` for any other producer.
    public let shards: Int?

    /// The names of the tests the shards' reconciliation reported failing, or `nil` where it cannot say — see ``ShardReconciliation/reportedTestFailures``; always `nil` for a run that did not reconcile.
    public let failedTests: [String]?

    public init(answer: String, exitCode: Int32, reconciled: Reconciled? = nil, runToken: String? = nil, shards: Int? = nil, failedTests: [String]? = nil) {
        self.answer = answer
        self.exitCode = exitCode
        self.reconciled = reconciled
        self.runToken = runToken
        self.shards = shards
        self.failedTests = failedTests
    }
}

public extension TestRunResult {
    /// What a ledger needs of a reconciliation: whether it was green, and whether SwiftSure cut a shard short.
    struct Reconciled: Sendable, Equatable {
        public let isGreen: Bool
        /// Whether a shard hit its wall-clock bound and SwiftSure ended it.
        public let stoppedBySift: Bool

        public init(isGreen: Bool, stoppedBySift: Bool) {
            self.isGreen = isGreen
            self.stoppedBySift = stoppedBySift
        }
    }
}
