//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import Testing

/// The test seam that lets a spawned `swift-sure post-tool-use` take a budget of a test's choosing.
struct PostToolUseHookBudgetTests {
    @Test
    func theVariableSetsTheBudgetInSeconds() {
        #expect(PostToolUseCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": "60"]) == 60)
        #expect(PostToolUseCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": "0"]) == 0)
    }

    @Test
    func anAbsentOrUnparsableVariableLeavesTheRealBudget() {
        let real = PostToolUseCommand.timeBudget(environment: [:])

        #expect(real == 1)
        #expect(PostToolUseCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": "soon"]) == real)
        #expect(PostToolUseCommand.timeBudget(environment: ["SWIFT_SURE_TEST_HOOK_BUDGET": ""]) == real)
    }
}
