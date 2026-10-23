//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// The limits a test moves for a spawned binary by environment: a value is read as seconds, and an absent or unparsable one leaves the real limit.
struct SpawnedLimitSeamTests {
    /// `SWIFT_SURE_TEST_GIT_LIMIT` sets the bound a defaulted git read gets.
    @Test func theGitLimitIsReadAsSeconds() {
        #expect(ChildDeadline.spawnedGitBound(in: ["SWIFT_SURE_TEST_GIT_LIMIT": "120"]) == 120)
        #expect(ChildDeadline.spawnedGitBound(in: ["SWIFT_SURE_TEST_GIT_LIMIT": "0.5"]) == 0.5)
    }

    /// Without `SWIFT_SURE_TEST_GIT_LIMIT`, or with a value that is not a positive number of seconds, a git read keeps the production bound.
    @Test(arguments: [nil, "", "soon", "0", "-3", "inf", "nan"])
    func anAbsentOrUnparsableGitLimitLeavesTheRealOne(value: String?) {
        let environment = value.map { ["SWIFT_SURE_TEST_GIT_LIMIT": $0] } ?? [:]

        #expect(ChildDeadline.spawnedGitBound(in: environment) == ChildDeadline.git)
    }

    /// `SWIFT_SURE_TEST_REPLAY_LIMIT` sets the replay's limit, in place of its time budget and the schema probe's.
    @Test func theReplayLimitIsReadAsSeconds() {
        #expect(HookReplay.spawnedLimit(in: ["SWIFT_SURE_TEST_REPLAY_LIMIT": "600"]) == 600)
        #expect(HookReplay.spawnedLimit(in: ["SWIFT_SURE_TEST_REPLAY_LIMIT": "1.5"]) == 1.5)
    }

    /// Without `SWIFT_SURE_TEST_REPLAY_LIMIT`, or with a value that is not a positive number of seconds, the replay keeps its real limits.
    @Test(arguments: [nil, "", "soon", "0", "-3", "inf", "nan"])
    func anAbsentOrUnparsableReplayLimitLeavesTheRealOnes(value: String?) {
        let environment = value.map { ["SWIFT_SURE_TEST_REPLAY_LIMIT": $0] } ?? [:]

        #expect(HookReplay.spawnedLimit(in: environment) == nil)
        #expect(HookReplay.timeBudget == 60)
        #expect(ExternalReplayHook.schemaProbeLimit == 30)
    }
}
