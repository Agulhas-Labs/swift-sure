//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A spliced result line in a shard's log claims no test, and the merge names it as garbled rather than only counting it unattributed.
struct ShardGarbledNameTests {
    private func reconcile(_ lines: [String], sourceLocation: SourceLocation = #_sourceLocation) throws -> ShardReconciliation {
        let test = try #require(TestIdentifier(enumerated: "GizmoTests/PalletTests/anOrdinaryPass()"), sourceLocation: sourceLocation)
        var read = RunTestOutcomes()
        for line in lines {
            read.read(line)
        }
        let plan = ShardPlan(
            shards: [ShardPlan.Shard(index: 1, tests: [test], predictedSeconds: 21)],
            requestedShards: 1,
            overheadSeconds: 20,
            estimatedTests: 0,
            estimatedSeconds: 1,
            displayNames: [:],
            lowering: nil
        )
        return ShardMerge.reconcile(plan: plan, outcomes: [ShardOutcome(outcomes: read, exitCode: 0, wallSeconds: 30, logPath: "/tmp/shard.log")])
    }

    /// The spliced name is counted unattributed and named garbled, as the unsharded inventory line names it.
    @Test
    func aSplicedNameIsNamedGarbled() throws {
        let merged = try reconcile([
            "✔ Test anOrdinaryPass() passed after 0.010 seconds.",
            "✔ Test anOrdinaryPass(ne() passed after 0.851 seconds.",
        ])

        #expect(merged.notes.contains { $0.hasPrefix("1 reported ending named no test the shard was given") }, "\(merged.notes)")
        #expect(merged.notes.contains("1 report line garbled (output lines spliced?): anOrdinaryPass(ne()"), "\(merged.notes)")
    }

    /// A clean shard carries no such sentence.
    @Test
    func aCleanShardNamesNothingGarbled() throws {
        let merged = try reconcile(["✔ Test anOrdinaryPass() passed after 0.010 seconds."])

        #expect(!merged.notes.contains { $0.contains("garbled") }, "\(merged.notes)")
    }
}
