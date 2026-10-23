//
// Copyright © Agulhas Labs
//

import Foundation
import SiftMCP
import Testing

/// The test seam that lets a spawned `swift-sure pre-tool-use` answer in place under a budget of a test's choosing.
struct InPlaceAnswerBudgetTests {
    @Test
    func theVariableSetsTheBudgetInSeconds() {
        #expect(InPlaceAnswer.budget(in: ["SWIFT_SURE_TEST_INPLACE_BUDGET": "60"]) == 60)
        #expect(InPlaceAnswer.budget(in: ["SWIFT_SURE_TEST_INPLACE_BUDGET": "0.001"]) == 0.001)
    }

    @Test
    func anAbsentUnparsableOrNonPositiveVariableLeavesTheRealBudget() {
        let real = InPlaceAnswer.budget(in: [:])

        #expect(real == InPlaceAnswer.timeBudget)
        #expect(InPlaceAnswer.liveBudget == real, "the suite runs with the variable unset")
        for value in ["soon", "", "0", "-1", "inf", "nan"] {
            #expect(InPlaceAnswer.budget(in: ["SWIFT_SURE_TEST_INPLACE_BUDGET": value]) == real, "\(value)")
        }
    }
}
