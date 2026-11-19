//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Covers the failing tests a multi-plan run records: named only when every plan can say what failed.
struct MultiPlanRecordedFailuresTests {
    @Test func `plans that all name no failures record none`() {
        #expect(TestRun.reportedTestFailures(ofPlans: [[], []]) == [])
    }

    @Test func `a failing plan beside a clean one records its names`() {
        #expect(TestRun.reportedTestFailures(ofPlans: [["Gizmo/spins()"], []]) == ["Gizmo/spins()"])
    }

    @Test func `no plans cannot say`() {
        #expect(TestRun.reportedTestFailures(ofPlans: []) == nil)
    }

    @Test func `a plan that cannot say makes the run unable to say`() {
        #expect(TestRun.reportedTestFailures(ofPlans: [nil, []]) == nil)
    }

    @Test func `a plan that cannot say hides the names of another`() {
        #expect(TestRun.reportedTestFailures(ofPlans: [["Widget/turns()"], nil]) == nil)
    }
}
