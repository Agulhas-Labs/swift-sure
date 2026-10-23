//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore

/// `flakes`' same-tree tier as `checkup` reads it, over the runs of one repository and every worktree of it.
public struct CheckupFlakes {
    /// The same-tree reading of the log at `fileURL` for the repository at `root`, or `nil` where the log holds no run there.
    public static func evidence(logAt fileURL: URL, root: String) -> CheckupFlakeEvidence? {
        guard case let .success(scope) = LogScope.resolve(root, inLogsAt: [fileURL]) else { return nil }
        let history = RunFailureHistory.of(RunScan.load(fileURL: fileURL, scope: scope, acrossWorktrees: true))
        let tests = history.sameTree.flatMap(\.tests).map { CheckupFlakeEvidence.Recorded(name: $0.name, failed: $0.failed, runs: $0.runs) }
        return CheckupFlakeEvidence(runs: history.measured - history.treeless, tests: tests)
    }
}
