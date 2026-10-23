//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers which skips the answer lists: one per test the run reported, however many share a name.
struct RunSkipListingTests {
    /// Swift Testing prints no suite name, so two suites' tests of one name are two skips and the listing accounts for the count.
    @Test
    func twoSuitesTestsOfOneNameAreTwoListedSkips() {
        var outcomes = RunTestOutcomes()
        outcomes.read("\u{200B}➜ Test same() skipped: \"first\"")
        outcomes.read("\u{200B}➜ Test same() skipped: \"second\"")

        #expect(outcomes["same()"]?.skipped == 2)
        #expect(outcomes.skips == [
            RunTestOutcomes.Skip(name: "same()", reason: "first"),
            RunTestOutcomes.Skip(name: "same()", reason: "second"),
        ])
    }

    /// Skips only the event stream carried are each listed, even under one name.
    @Test
    func streamOnlySkipsOfOneNameAreEachListed() {
        var outcomes = RunTestOutcomes()
        outcomes.recordStreamed(RunTestOutcomes.Attempt(ending: .skipped), of: "same()")
        outcomes.recordStreamed(RunTestOutcomes.Attempt(ending: .skipped), of: "same()")

        #expect(outcomes.skips.count == 2)
    }
}
