//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftMCP
import Testing

/// The test seam that lets a spawned `swift-sure stop` take a budget of a test's choosing, the post-tool-use hook's variable.
struct StopHookBudgetTests {
    @Test
    func theVariableSetsTheBudgetInSeconds() {
        #expect(StopCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": "60"]) == 60)
        #expect(StopCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": "0"]) == 0)
    }

    @Test
    func anAbsentOrUnparsableVariableLeavesTheRealBudget() {
        let real = StopCommand.timeBudget(environment: [:])

        #expect(real == StopBuildGate.timeBudget)
        #expect(StopCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": "soon"]) == real)
        #expect(StopCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": ""]) == real)
    }
}
