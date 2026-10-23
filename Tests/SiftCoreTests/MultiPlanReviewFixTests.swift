//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Pins the review fixes to multi-plan runs: Xcode's own sanitizer keys, tied plans splitting, the plan names read off a build's files, and the per-plan notes and re-run line.
@Suite(.temporaryDirectories)
struct MultiPlanReviewFixTests {
    private static func tests(_ names: [String]) -> [TestIdentifier] {
        names.compactMap { TestIdentifier(enumerated: "GizmoTests/Gizmo/\($0)()") }
    }

    /// Xcode stores the address sanitizer as `{ "enabled": true }` and the other two as plain booleans; each is refused, under its own key.
    @Test(arguments: [
        #""addressSanitizer": { "enabled": true }"#,
        #""threadSanitizerEnabled": true"#,
        #""undefinedBehaviorSanitizerEnabled": true"#,
    ])
    func aPlanSwitchingOnAnyOfXcodesSanitizersIsRefused(option: String) throws {
        let root = try TemporaryDirectory.make("multi-plan-real-sanitizer")
        let plans = root.appendingPathComponent("TestPlans")
        try FileManager.default.createDirectory(at: plans, withIntermediateDirectories: true)
        let document = #"{ "configurations": [], "defaultOptions": { \#(option) }, "testTargets": [], "version": 1 }"#
        try Data(document.utf8).write(to: plans.appendingPathComponent("Excluding.xctestplan"))
        let key = String(option.split(separator: "\"")[0])

        let result = TestRun(request: MultiPlanRunTests.request(in: root), environment: MultiPlanRunTests.fake(root: root).environment(PlanRunFake.Launches())).run()

        #expect(result.exitCode == 64, "\(result.answer)")
        #expect(result.answer.contains("switches on \(key)"), "\(result.answer)")
    }

    @Test
    func aSanitizerSwitchedOffIsNotCounted() {
        let document = #"{ "defaultOptions": { "threadSanitizerEnabled": false, "addressSanitizer": { "enabled": false } } }"#

        #expect(TestPlanSanitizers.enabled(in: Data(document.utf8)).isEmpty)
    }

    /// Two plans tied for longest, 100 s each, on four devices with a 10 s call overhead: splitting either alone leaves the run at 110 s, so only splitting both reaches 60 s.
    @Test
    func twoPlansTiedForLongestAreBothSplit() {
        let names = (1 ... 10).map { "t\($0)" }
        let plan = MultiPlanShardPlanner.plan(
            [
                MultiPlanShardPlanner.PlanTests(plan: "Fast", tests: Self.tests(names)),
                MultiPlanShardPlanner.PlanTests(plan: "Slow", tests: Self.tests(names)),
            ],
            shards: 4,
            overheadSeconds: 10,
            duration: { _ in 10 }
        )

        #expect(plan.shards.count == 4)
        #expect(plan.predictedMakespan == 60)
    }

    @Test
    func aPlanNameIsCutBeforeTheSdkComponentEvenWhereTheArchitectureHoldsAnUnderscore() {
        let written = [
            "TestDemo_Default_iphonesimulator27.0-undefined_arch.xctestrun",
            "TestDemo_Unit_Tests_iphonesimulator27.0-arm64.xctestrun",
            "TestDemo_Mac2_macosx15.0-undefined_arch.xctestrun",
        ]

        #expect(TestRun.planNames(in: written, scheme: "TestDemo") == ["Default", "Unit_Tests", "Mac2"])
    }

    @Test
    func aPlansProjectionCountsItsOwnTestsWithNoRecordedDuration() {
        let plan = MultiPlanShardPlanner.plan(
            [
                MultiPlanShardPlanner.PlanTests(plan: "Fast", tests: Self.tests(["a", "b"])),
                MultiPlanShardPlanner.PlanTests(plan: "Slow", tests: Self.tests(["c"])),
            ],
            shards: 1,
            overheadSeconds: 10,
            duration: { $0.function == "a()" ? 3 : nil }
        )

        #expect(plan.projected(plan: "Fast").estimatedTests == 1)
        #expect(plan.projected(plan: "Slow").estimatedTests == 1)
    }

    /// Alpha's tests fail; Beta reports none ended, so it fails only on missing tests, which a `--only` re-run cannot name.
    @Test
    func theRerunLineLeavesOutAPlanThatFailedOnlyOnMissingTests() throws {
        let root = try TemporaryDirectory.make("multi-plan-rerun-missing")
        var fake = MultiPlanAnswerTests.fake(root: root)
        fake.failing = ["Alpha"]
        fake.silent = ["Beta"]

        let answer = TestRun(request: MultiPlanRunTests.request(in: root), environment: fake.environment(PlanRunFake.Launches())).run().answer
        let rerun = answer.split(separator: "\n").first { $0.contains("--shards 1 --only") }.map(String.init) ?? ""

        #expect(rerun.contains("--plan Alpha"), "\(answer)")
        #expect(!rerun.contains("--plan Beta"), "\(answer)")
    }

    @Test
    func aPlanNamedTwiceIsOnePlanAndNoMultiPlanRun() {
        let request = TestRunRequest(
            scheme: "TestDemo",
            deviceTypeName: "iPhone 17",
            plans: ["Default", "Default"],
            requestedShards: 2,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            repositoryRoot: URL(fileURLWithPath: "/tmp"),
            executable: URL(fileURLWithPath: "/tmp/swift-sure")
        )

        #expect(!request.isMultiPlan)
        #expect(request.plan == "Default")
    }
}
