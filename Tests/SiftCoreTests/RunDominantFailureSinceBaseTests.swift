//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the dominant-failure clause on a feature branch, where the changed-files count carries the base it was measured since.
struct RunDominantFailureSinceBaseTests {
    /// A branch whose commits touched none of the failing files has zero changed files exactly as a clean default branch does, and the empty-tree clause is owed the same.
    @Test
    func aZeroCountSinceTheBaseUnlocksTheEmptyTreeClauseExactlyAsAPlainZeroDoes() {
        let plain = Self.block(changedFiles: .of([]))
        let sinceBase = Self.block(changedFiles: .sinceBase([], base: "main"))

        #expect(plain[2].contains("EMPTY accessibility read"))
        #expect(sinceBase[2] == plain[2])
    }

    @Test
    func aFailureInAFileTheBranchChangedStillWithholdsTheClause() {
        let block = Self.block(changedFiles: .sinceBase(["BinLabelTests.swift"], base: "main"))

        #expect(!block[2].contains("EMPTY accessibility read"))
    }

    @Test
    func theCountSinceTheBaseReadsAsAChangedFileCountOnlyWhereThereIsOne() {
        #expect(RunFailureCensus.ChangedFileCount.count(3).changedCount == 3)
        #expect(RunFailureCensus.ChangedFileCount.countSinceBase(0, base: "main").changedCount == 0)
        #expect(RunFailureCensus.ChangedFileCount.unavailable("no").changedCount == nil)
    }

    private static func block(changedFiles: RunChangedFiles) -> [String] {
        let messages = [
            #"Expectation failed: (labels → "").contains(bay.signage → "Sprockets")"#,
            #"Expectation failed: (labels → "").contains(crate.signage → "Rivets")"#,
            #"Expectation failed: (labels → "") == (expected → "Cogs")"#,
            "Expectation failed: (stacked → 3) == (wanted → 4)",
        ]
        let files = [
            "BinLabelTests", "ChartGridTests", "ConveyorBeltTests", "HopperGaugeTests",
            "PalletTests", "BackorderTests", "GridTests", "ListingTests",
        ]
        let failures = (0 ..< 40).map { index in
            RunFailureShape.Failure(
                name: "aTestNamed\(index)()",
                location: "\(files[index % files.count]).swift:\(index + 1):9",
                message: messages[index % messages.count]
            )
        }
        let restoration = SimulatorAccessibility.Restoration(
            udid: "00000000-0000-0000-0000-000000000000",
            state: .restored
        )
        return RunFailureShape.of(failures, changedFiles: changedFiles, accessibility: [restoration]).rendered()
    }
}
