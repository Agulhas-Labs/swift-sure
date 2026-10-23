//
// Copyright © Agulhas Labs
//

/// What the run log holds for `checkup`'s flaky check: `flakes`' same-tree tier, and how many runs it was read over.
public struct CheckupFlakeEvidence: Sendable, Equatable {
    /// The runs that recorded both their tree and their command line, the only runs the same-tree tier reads.
    public let runs: Int
    /// Every test the run log records both failing and passing on one tree under one command line.
    public let tests: [Recorded]

    public init(runs: Int, tests: [Recorded]) {
        self.runs = runs
        self.tests = tests
    }
}

public extension CheckupFlakeEvidence {
    /// One test as the run recorded it, with its failures and the runs of the trees it both failed and passed on.
    struct Recorded: Sendable, Equatable {
        public let name: String
        public let failed: Int
        public let runs: Int

        public init(name: String, failed: Int, runs: Int) {
            self.name = name
            self.failed = failed
            self.runs = runs
        }
    }
}
