//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// What a range ending at another revision does to the statuses of the checks: a run records the working tree, not that revision.
struct CheckupRangeRuleTests {
    private static let ran = CheckupChecks(Dictionary(uniqueKeysWithValues: CheckupCheck.allCases.map { ($0, .checked(basis: "recorded", bound: nil)) }))

    /// The three recorded-run checks are not checked, and the checks that read the working tree say so beside their name.
    @Test
    func aRangeEndingElsewhereMovesTheRecordedRunChecksAndMarksTheRest() {
        let applied = Self.ran.applying(rangeEnding: .revision("feature"), atCleanHead: false)

        for check in CheckupCheck.allCases where check.readsRecordedRuns {
            guard case .notChecked = applied.status(of: check) else {
                Issue.record("\(check.name) stayed checked")
                continue
            }
        }
        for check in CheckupCheck.allCases where check.readsWorkingTree {
            #expect(applied.status(of: check) == .checked(basis: "read against the working tree, not feature; recorded", bound: nil))
        }

        #expect(applied.rendered.contains("test runs (a run records the working tree's content, and this range ends at feature)"))
        #expect(applied.rendered.contains("changed-line coverage (a run records"))
    }

    /// The commit `HEAD` names, with a clean tree, is the content a run recorded: nothing moves and nothing is marked.
    @Test
    func aCleanTreeAtHeadChangesNothing() {
        #expect(Self.ran.applying(rangeEnding: .revision("HEAD"), atCleanHead: true) == Self.ran)
    }

    /// A range ending at the working tree is the content a run recorded.
    @Test
    func theWorkingTreeChangesNothing() {
        #expect(Self.ran.applying(rangeEnding: .workingTree, atCleanHead: false) == Self.ran)
    }
}
