//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A run that names no plan, on a scheme with several, runs the scheme's default plan — as `xcodebuild test` does — rather than refusing because its build wrote one `.xctestrun` per plan.
@Suite(.temporaryDirectories)
struct TestRunDefaultPlanTests {
    @Test
    func aRunNamingNoPlanRunsTheSchemesDefaultPlan() throws {
        let root = try TemporaryDirectory.make("default-plan")
        let launches = PlanRunFake.Launches()
        var fake = PlanRunFake(root: root, tests: ["Default": ["DemoUnitTests/GizmoTests/adds()"], "Excluding": [], "Retrying": []])
        fake.schemes = PlanRunFake.scheme(plans: ["Default", "Excluding", "Retrying"])

        let result = TestRun(request: PlanRunFake.request(in: root), environment: fake.environment(launches)).run()

        let named = launches.taken().compactMap(PlanRunFake.xctestrun(in:))

        #expect(!result.answer.contains("one run runs one plan"))
        #expect(!named.isEmpty)
        #expect(named.allSatisfy { $0 == PlanRunFake.xctestrunName(plan: "Default") })
    }

    @Test
    func aSchemeThatCannotBeReadStillRefusesSeveralFiles() throws {
        let root = try TemporaryDirectory.make("default-plan-unread")
        let launches = PlanRunFake.Launches()
        let fake = PlanRunFake(root: root, tests: ["Default": ["DemoUnitTests/GizmoTests/adds()"], "Excluding": []])

        let result = TestRun(request: PlanRunFake.request(in: root), environment: fake.environment(launches)).run()

        #expect(result.answer.contains("one run runs the plans it is told: name one with --plan, several by repeating it, or all with --all-plans"))
        #expect(result.exitCode == 64)
    }
}
