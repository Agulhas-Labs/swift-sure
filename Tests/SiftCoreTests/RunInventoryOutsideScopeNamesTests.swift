//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the inventory line's clause for tests outside the run's scope: the number is the tests', and the targets that declare them are named.
struct RunInventoryOutsideScopeNamesTests {
    private static func clause(_ outside: [(String, Int)]) -> String {
        let reconciliation = RunReconciliation(
            counts: ReconciliationCounts(expected: 3, ran: 3, passed: 3, failed: 0, skipped: 0, missing: 0, duplicated: 0),
            scope: RunReconciliation.Scope(manifest: "Package.swift", targets: ["GizmoTests"], conditionalTargets: false, logPath: "run.log"),
            iterations: 1,
            missing: [],
            shortfalls: [],
            duplicated: [],
            failed: [],
            excluded: [],
            undecided: [],
            unclaimed: [],
            outsideScope: outside.map { RunReconciliation.OutsideScope(target: $0.0, declared: $0.1) },
            notes: []
        )
        return RunInventoryCheck.reconciled(reconciliation).lines.first ?? ""
    }

    @Test
    func twoTargetsOfOneTestEachAreNamedBare() {
        #expect(Self.clause([("AlphaTests", 1), ("BetaTests", 1)]) == "inventory: 3 declared, 3 reported (2 outside this run's scope: AlphaTests, BetaTests)")
    }

    /// Three targets are named, then the targets left are counted, and the counts of both add up to the number in front.
    @Test
    func aTargetDeclaringSeveralTestsCarriesItsCountAndTheRestAreCounted() {
        let outside = [("AlphaTests", 3), ("BackorderTests", 1), ("BadgeTests", 2), ("BetaTests", 3)]

        #expect(Self.clause(outside) == "inventory: 3 declared, 3 reported (9 outside this run's scope: AlphaTests ×3, BackorderTests, BadgeTests ×2, +1 more)")
    }

    @Test
    func noTargetsOutsideTheScopePrintNothing() {
        #expect(Self.clause([]) == "inventory: 3 declared, 3 reported")
    }
}
