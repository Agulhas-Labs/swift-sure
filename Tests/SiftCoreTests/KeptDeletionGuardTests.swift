//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Pins the guards on the kept-deletion reading that no other suite fails without.
@Suite(.temporaryDirectories)
struct KeptDeletionGuardTests {
    private static func ledgerStore(dropped paths: [String], at instant: Double) throws -> IndexStore {
        let store = try TestSources.makeStore()
        var ledger = DeletionLedger(metaValue: nil)
        ledger.record(paths, at: instant)
        try store.setMetaValue(ledger.metaValue, forKey: DeletionLedger.metaKey)
        return store
    }

    /// A refusal that counts a deleted declaring file changed, beside a judge that finds the same file a kept deletion, is a file a rebuild fixes: the header must not say a clean build is needed.
    @Test
    func aRefusedFileTheJudgeCallsKeptDoesNotReadUntilACleanBuild() throws {
        let store = try TestSources.makeStore()
        let judge = OccurrenceFreshness(store: store, buildAnchor: 0) { $0 }
        judge.record(.keptDeletion, for: "Sources/A.swift")
        let refusal = SemanticRefusal(path: "Sources/A.swift", reason: .modifiedSinceBuild, symbol: "a()", kind: .function)

        let axis = SemanticAxis.of(refusals: [refusal], occurrences: judge)
        let unrefused = SemanticAxis.of(refusals: [], occurrences: judge)

        #expect(axis.rendered == "stale since last build (1 cited file deleted: Sources/A.swift)")
        #expect(unrefused.rendered == "stale until a clean build (1 cited file deleted: Sources/A.swift)")
    }

    /// An absolute path is never kept, and the answer is reached before the ledger is read.
    @Test
    func anAbsolutePathIsNeverKeptAndNeverReadsTheLedger() throws {
        let root = try TestSources.makeTempDirectory()
        let outside = try TestSources.makeTempDirectory().appendingPathComponent("Gone.swift").path
        let store = try Self.ledgerStore(dropped: [outside], at: 100)
        let kept = KeptDeletions()

        let verdict = kept.isKept(outside, anchor: 200, stores: [], root: root, index: store)

        #expect(!verdict)
        #expect(kept.ledgerReads == 0)
    }

    /// Several cited deletions in one query read the ledger once.
    @Test
    func severalCitedDeletionsReadTheLedgerOnce() throws {
        let root = try TestSources.makeTempDirectory()
        let store = try Self.ledgerStore(dropped: ["A.swift", "B.swift"], at: 100)
        let kept = KeptDeletions()

        for path in ["A.swift", "B.swift", "C.swift"] {
            _ = kept.isKept(path, anchor: 200, stores: [], root: root, index: store)
        }

        #expect(kept.ledgerReads == 1)
    }

    /// One file given a plain deletion and a kept one is counted as the plain deletion, in either order, by the files view.
    @Test
    func theFilesViewKeepsThePlainDeletionInEitherOrder() {
        for states in [[OccurrenceState.deleted, .keptDeletion], [.keptDeletion, .deleted]] {
            let collector = WhereFilesCollector()
            for state in states {
                collector.recordCode(path: "Gone.swift", lines: [1], state: state)
            }

            #expect(collector.files["Gone.swift"]?.state == .deleted, "\(states)")
        }
    }

    /// The same file reached twice by the affected walk keeps the plain deletion in either order.
    @Test
    func theAffectedMergeKeepsThePlainDeletionInEitherOrder() {
        func evidence(_ state: OccurrenceState) -> AffectedRenderer.Evidence {
            AffectedRenderer.Evidence(depth: 1, resolved: true, state: state, path: "Gone.swift", line: 1)
        }

        #expect(evidence(.deleted).merged(with: evidence(.keptDeletion)).state == .deleted)
        #expect(evidence(.keptDeletion).merged(with: evidence(.deleted)).state == .deleted)
        #expect(evidence(.keptDeletion).merged(with: evidence(.live)).state == .live)
    }
}
