//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A run over several plans answers once: one verdict, a line per plan, the totals, every shard, and the slowest tests across the plans — not a block per plan.
@Suite(.temporaryDirectories)
struct MultiPlanAnswerTests {
    static func fake(root: URL) -> PlanRunFake {
        var fake = PlanRunFake(root: root, tests: [
            "Alpha": ["DemoUnitTests/GizmoTests/adds()", "DemoUnitTests/GizmoTests/shared()"],
            "Beta": ["DemoLogicTests/GizmoTests/spins()", "DemoUnitTests/GizmoTests/shared()"],
            "Gamma": [],
        ])
        fake.schemes = PlanRunFake.scheme(plans: ["Alpha", "Beta", "Gamma"])
        fake.failing = ["Beta"]
        fake.endings = ["shared()": 9, "adds()": 3, "spins()": 2]
        return fake
    }

    static func run(in root: URL) -> TestRun.Result {
        TestRun(request: MultiPlanRunTests.request(in: root), environment: fake(root: root).environment(PlanRunFake.Launches())).run()
    }

    @Test
    func aMultiPlanRunOpensWithOneVerdictNamingTheFailingPlansAndAnswersEachPlanOnALine() throws {
        let root = try TemporaryDirectory.make("multi-plan-answer")

        let result = Self.run(in: root)
        let lines = result.answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(result.exitCode != 0)
        #expect(lines.first?.hasPrefix("✘ swift-sure test — Beta: ") == true, "\(result.answer)")
        #expect(lines.count { $0.hasPrefix("✔ ") || $0.hasPrefix("✘ ") } == 1)
        #expect(lines.contains { $0.hasPrefix("  Alpha: expected 2 · ran 2 · passed 2") })
        #expect(lines.contains { $0.hasPrefix("  Beta: expected 2") })
        #expect(lines.contains("  Gamma: no tests enumerated"))
        #expect(lines.contains { $0.hasPrefix("  total: expected 4") })
        #expect(!lines.contains { $0.hasPrefix("plan ") })
        #expect(lines.contains { $0.hasPrefix("shard 1 (plan ") })
    }

    @Test
    func theSlowestTestsAreListedOnceAcrossPlansNamingAPlanOnlyWhereATestRanInSeveral() throws {
        let root = try TemporaryDirectory.make("multi-plan-slowest")

        let answer = Self.run(in: root).answer
        let lines = answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(lines.count { $0 == "slowest:" } == 1, "\(answer)")
        #expect(lines.contains { $0.hasSuffix("Alpha: DemoUnitTests/GizmoTests/shared()") })
        #expect(lines.contains { $0.hasSuffix("Beta: DemoUnitTests/GizmoTests/shared()") })
        #expect(lines.contains { $0.hasSuffix("  DemoUnitTests/GizmoTests/adds()") })
    }

    @Test
    func theRerunLineNamesOnlyTheFailingPlans() throws {
        let root = try TemporaryDirectory.make("multi-plan-rerun")

        let answer = Self.run(in: root).answer
        let rerun = answer.split(separator: "\n").first { $0.contains("--shards 1 --only") }.map(String.init) ?? ""

        #expect(rerun.contains("--plan Beta"), "\(answer)")
        #expect(!rerun.contains("--plan Alpha"))
        #expect(!rerun.contains("--all-plans"))
    }
}
