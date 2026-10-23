//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers planning a run over several test plans: every (plan, test) item is placed, each (shard, plan) call is charged its own overhead, and a plan's tests stay on one shard unless splitting them pays.
struct MultiPlanShardPlannerTests {
    private static func tests(_ names: [String]) -> [TestIdentifier] {
        names.compactMap { TestIdentifier(enumerated: "GizmoTests/Gizmo/\($0)()") }
    }

    /// A test both plans enumerate is planned once in each, and the one shard running both plans pays two overheads: 20 + 20 + three 5 s items.
    @Test
    func aShardHoldingTwoPlansIsChargedTwoOverheads() {
        let plan = MultiPlanShardPlanner.plan(
            [
                MultiPlanShardPlanner.PlanTests(plan: "Fast", tests: Self.tests(["shared", "alone"])),
                MultiPlanShardPlanner.PlanTests(plan: "Slow", tests: Self.tests(["shared"])),
            ],
            shards: 1,
            overheadSeconds: 20,
            duration: { _ in 5 }
        )

        #expect(plan.shards.count == 1)
        #expect(plan.shards.first?.segments.map(\.plan) == ["Fast", "Slow"])
        #expect(plan.shards.first?.segments.map { $0.tests.map(\.enumerated) } == [
            ["GizmoTests/Gizmo/alone()", "GizmoTests/Gizmo/shared()"],
            ["GizmoTests/Gizmo/shared()"],
        ])
        #expect(plan.shards.first?.predictedSeconds == 55)
    }

    /// Two plans of ten 1 s tests on two shards each run whole on a shard of their own (30 s), rather than both split across both (two calls, 50 s each).
    @Test
    func aPlanStaysOnOneShardWhereSplittingItDoesNotPay() {
        let names = (1 ... 10).map { "t\($0)" }
        let plan = MultiPlanShardPlanner.plan(
            [
                MultiPlanShardPlanner.PlanTests(plan: "Fast", tests: Self.tests(names)),
                MultiPlanShardPlanner.PlanTests(plan: "Slow", tests: Self.tests(names)),
            ],
            shards: 2,
            overheadSeconds: 20,
            duration: { _ in 1 }
        )

        #expect(plan.shards.map { $0.segments.map(\.plan) } == [["Fast"], ["Slow"]])
        #expect(plan.shards.map(\.predictedSeconds) == [30, 30])
    }

    /// A plan carrying most of the work is split across both shards where that shortens the run: 241 s and 220 s against 421 s whole.
    @Test
    func aLongPlanIsSplitWhereThatPaysForTheExtraCall() {
        let plan = MultiPlanShardPlanner.plan(
            [
                MultiPlanShardPlanner.PlanTests(plan: "Fast", tests: Self.tests(["a", "b", "c", "d"])),
                MultiPlanShardPlanner.PlanTests(plan: "Slow", tests: Self.tests(["e"])),
            ],
            shards: 2,
            overheadSeconds: 20,
            duration: { $0.function == "e()" ? 1 : 100 }
        )

        #expect(plan.shards.map { $0.segments.map(\.plan) } == [["Fast", "Slow"], ["Fast"]])
        #expect(plan.shards.map(\.predictedSeconds) == [241, 220])
    }

    /// One plan's projection keeps each of its segments under the index of the shard that runs it.
    @Test
    func aProjectionKeepsTheShardIndexEachSegmentRunsOn() {
        let plan = MultiPlanShardPlanner.plan(
            [
                MultiPlanShardPlanner.PlanTests(plan: "Fast", tests: Self.tests(["a"])),
                MultiPlanShardPlanner.PlanTests(plan: "Slow", tests: Self.tests(["b"])),
            ],
            shards: 2,
            overheadSeconds: 20,
            duration: { _ in 100 }
        )
        let projected = plan.projected(plan: "Slow")

        #expect(projected.shards.map(\.index) == [2])
        #expect(projected.shards.map { $0.tests.map(\.enumerated) } == [["GizmoTests/Gizmo/b()"]])
        #expect(projected.shards.map(\.predictedSeconds) == [120])
    }
}
