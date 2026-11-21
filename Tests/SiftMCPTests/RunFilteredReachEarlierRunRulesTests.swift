//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// Covers the two rules that keep an earlier run's ids from being counted where they should not be: a tree that moved while the run ran, and a run that reports more ids than the ledger keeps.
@Suite(.temporaryDirectories)
struct RunFilteredReachEarlierRunRulesTests {
    @Test
    func aTreeEditedWhileTheSecondRunRanCountsNoEarlierRun() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: RunFilteredReachEarlierRunTests.source)
        try RunFilteredReachEarlierRunTests.dirty(repository)
        _ = try await RunInventoryNoteTests.run(in: repository, printing: RunFilteredReachEarlierRunTests.green("testA"), exiting: 0, extraArguments: ["--package-path", repository.path, "--filter", "PalletTests"])
        // The package is the checkout the command builds, so its tree is the one the proof is keyed on.
        let edit = "echo moved >> '\(repository.appendingPathComponent("Notes.txt").path)'"
        let (second, _) = try await RunInventoryNoteTests.run(
            in: repository, printing: RunFilteredReachEarlierRunTests.green("testB"), exiting: 0, extraArguments: ["--package-path", repository.path, "--filter", "GadgetTests"], beforePrinting: edit
        )

        #expect(RunFilteredReachEarlierRunTests.note(second.printed).first?.contains("run swift test --filter GizmoTests.PalletTests") == true, "\(second.printed)")
    }

    @Test
    func aRunReportingMoreIdsThanTheLimitFilesNoneForLaterRunsToCount() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: RunFilteredReachEarlierRunTests.source)
        try RunFilteredReachEarlierRunTests.dirty(repository)
        _ = try await RunInventoryNoteTests.run(
            in: repository, printing: RunFilteredReachEarlierRunTests.green("testA"), exiting: 0, extraArguments: ["--filter", "PalletTests"], configuring: { $0.recordedIdentifierLimit = 0 }
        )
        let (second, _) = try await RunInventoryNoteTests.run(in: repository, printing: RunFilteredReachEarlierRunTests.green("testB"), exiting: 0, extraArguments: ["--filter", "GadgetTests"])

        #expect(RunFilteredReachEarlierRunTests.note(second.printed).first?.contains("run swift test --filter GizmoTests.PalletTests") == true, "\(second.printed)")
    }
}
