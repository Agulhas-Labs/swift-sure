//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

@Suite("CheckupFlakyCheck")
struct CheckupFlakyCheckTests {
    private let spin = TestSymbol(target: "GizmoTests", suite: "Depot", function: "spin()", style: .swiftTesting)
    private let wobble = TestSymbol(target: "GizmoTests", suite: "Depot", function: "wobble()", style: .swiftTesting)

    private func evidence(_ names: String...) -> CheckupFlakeEvidence {
        CheckupFlakeEvidence(runs: 9, tests: names.map { CheckupFlakeEvidence.Recorded(name: $0, failed: 2, runs: 5) })
    }

    @Test func aReachedTestRecordedFlakyIsAFinding() {
        let outcome = CheckupFlakyCheck.outcome(evidence: evidence("spin()"), reached: [spin])

        #expect(outcome.status == .checked(basis: "over 9 runs", bound: nil))
        #expect(outcome.findings.map(\.text) == ["GizmoTests.Depot/spin() failed and passed on identical bytes, failing 2 of 5 runs"])
        #expect(outcome.findings.first?.findingClass == .flaky)
        #expect(outcome.findings.first?.command.hasSuffix("flakes 'spin()'") == true)
    }

    @Test func aTestTheChangeDidNotReachIsNoFinding() {
        let outcome = CheckupFlakyCheck.outcome(evidence: evidence("spin()"), reached: [wobble])

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .checked(basis: "over 9 runs", bound: nil))
    }

    @Test func aDottedAndASlashedSpellingOfOneNameMatch() {
        #expect(CheckupFlakyCheck.names(spin, "GizmoTests/Depot/spin()"))
        #expect(CheckupFlakyCheck.names(spin, "Depot.spin()"))
        #expect(CheckupFlakyCheck.names(spin, "GizmoTests.Depot/spin()"))
    }

    @Test func aFragmentOfANameIsNoMatch() {
        #expect(!CheckupFlakyCheck.names(spin, "pin()"))
        #expect(!CheckupFlakyCheck.names(spin, "Depot"))
    }

    @Test func anXCTestLogNameMatchesItsMethod() {
        let legacy = TestSymbol(target: "GizmoTests", suite: "LegacyTests", function: "testOldMath", style: .xcTest)

        #expect(CheckupFlakyCheck.names(legacy, "-[GizmoTests.LegacyTests testOldMath]"))
        #expect(!CheckupFlakyCheck.names(legacy, "-[GizmoTests.Depot testOldMath]"))
    }

    @Test func noRunWithATreeAndACommandLineIsNotChecked() {
        let none = CheckupFlakyCheck.outcome(evidence: nil, reached: [spin])
        let treeless = CheckupFlakyCheck.outcome(evidence: CheckupFlakeEvidence(runs: 0, tests: []), reached: [spin])
        for outcome in [none, treeless] {
            #expect(outcome.status == .notChecked(reason: "no recorded run with a tree and a command line"))
            #expect(outcome.findings.isEmpty)
        }
    }

    @Test func noReachedTestIsNotChecked() {
        let outcome = CheckupFlakyCheck.outcome(evidence: evidence("spin()"), reached: [])

        #expect(outcome.status == .notChecked(reason: "no reached test"))
    }
}
