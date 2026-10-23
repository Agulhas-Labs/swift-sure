//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A run over several plans builds once, runs each plan's tests from its own `.xctestrun` on one pool of devices, and deletes every device it created — each but the last as soon as its own calls are done.
@Suite(.temporaryDirectories)
struct MultiPlanRunTests {
    static let plans = ["Default", "Excluding", "Retrying"]

    static func fake(root: URL) -> PlanRunFake {
        var fake = PlanRunFake(root: root, tests: [
            "Default": ["DemoUnitTests/GizmoTests/adds()", "DemoUnitTests/GizmoTests/subtracts()", "DemoUnitTests/GizmoTests/divides()"],
            "Excluding": ["DemoLogicTests/GizmoTests/spins()"],
            "Retrying": ["DemoLogicTests/GizmoTests/turns()"],
        ])
        fake.schemes = PlanRunFake.scheme(plans: plans)
        fake.holdsFirstCallForDelete = true
        return fake
    }

    static func request(in root: URL) -> TestRunRequest {
        TestRunRequest(
            scheme: "TestDemo",
            deviceTypeName: "iPhone 17",
            allPlans: true,
            requestedShards: 2,
            workingDirectory: root,
            repositoryRoot: root,
            executable: root.appendingPathComponent("swift-sure")
        )
    }

    @Test
    func everyPlanRunsFromOneBuildAndEveryDeviceIsDeleted() throws {
        let root = try TemporaryDirectory.make("multi-plan")
        let launches = PlanRunFake.Launches()
        let fake = Self.fake(root: root)

        _ = TestRun(request: Self.request(in: root), environment: fake.environment(launches)).run()

        let builds = launches.taken().filter { $0.contains("build-for-testing") }
        #expect(builds.count == 1)
        #expect(builds.allSatisfy { !$0.contains("-testPlan") })
        let segments = launches.taken().filter { $0.contains("test-without-building") && !$0.contains("-enumerate-tests") }
        for (plan, tests) in fake.tests {
            let ran = segments.filter { PlanRunFake.xctestrun(in: $0) == PlanRunFake.xctestrunName(plan: plan) }.joined().joined(separator: " ")
            #expect(tests.allSatisfy { ran.contains(URL(fileURLWithPath: $0).lastPathComponent) }, "plan \(plan)")
        }
        try Self.expectEveryDeviceDeleted(fake)
    }

    @Test
    func aFailingSegmentStillDeletesEveryDevice() throws {
        let root = try TemporaryDirectory.make("multi-plan-failing")
        let launches = PlanRunFake.Launches()
        var fake = Self.fake(root: root)
        fake.failing = ["Excluding"]

        let result = TestRun(request: Self.request(in: root), environment: fake.environment(launches)).run()

        #expect(result.exitCode != 0)
        try Self.expectEveryDeviceDeleted(fake)
    }

    @Test
    func aPlanThatSwitchesOnASanitizerIsRefusedBeforeTheBuild() throws {
        let root = try TemporaryDirectory.make("multi-plan-sanitizer")
        let plans = root.appendingPathComponent("TestPlans")
        try FileManager.default.createDirectory(at: plans, withIntermediateDirectories: true)
        // Any option key ending in the suffix counts, so the fixture's is a placeholder rather than one of Xcode's.
        let key = "gizmo" + "Sanitizer"
        let document = #"{ "configurations": [{ "name": "Gizmo", "options": { "\#(key)": { "enabled": true } } }], "defaultOptions": {}, "testTargets": [], "version": 1 }"#
        try Data(document.utf8).write(to: plans.appendingPathComponent("Excluding.xctestplan"))
        let launches = PlanRunFake.Launches()

        let result = TestRun(request: Self.request(in: root), environment: Self.fake(root: root).environment(launches)).run()

        #expect(result.exitCode == 64)
        #expect(result.answer.contains("switches on \(key), which builds products of its own that a run over several plans from one build cannot share: run it alone with --plan Excluding"))
        #expect(launches.taken().isEmpty)
    }

    /// At most the shards asked for were created, each was deleted once, and one went while another device's call was still running.
    static func expectEveryDeviceDeleted(_ fake: PlanRunFake, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let calls = fake.simctlCalls.taken()
        let created = calls.count { $0.dropFirst().first == "create" }
        let deleted = calls.filter { $0.dropFirst().first == "delete" }.compactMap(\.last)
        #expect((1 ... 2).contains(created), sourceLocation: sourceLocation)
        #expect(deleted.count == created, sourceLocation: sourceLocation)
        #expect(Set(deleted).count == created, sourceLocation: sourceLocation)
        #expect(!fake.deletedDuring.taken().isEmpty, "no device was deleted while another still ran", sourceLocation: sourceLocation)
    }
}
