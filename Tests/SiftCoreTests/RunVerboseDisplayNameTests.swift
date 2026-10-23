//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Under `--verbose` Swift Testing names a display-named test `"Display named check" (aka 'displayNamed(_:)')`, and the answer names it as the plain log does.
struct RunVerboseDisplayNameTests {
    /// The failing run in `fixture`, read as `swift test` reads it, and its rendered answer.
    private static func realRun(_ fixture: String) throws -> (report: RunReport, answer: String) {
        let report = try TestSources.runReport(fixture, invokedAs: ["swift", "test"], exitCode: 1)
        let answer = RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"))
            .render(report, exitCode: 1, logURL: nil)
        return (report, answer)
    }

    /// Every failing test is named, each located issue listed, and no argument's count line is taken for the run's.
    private static func expectEveryFailureNamed(in fixture: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (report, answer) = try realRun(fixture)

        #expect(report.verdict?.state == .failed, sourceLocation: sourceLocation)
        #expect(report.tally?.tests == 3, sourceLocation: sourceLocation)
        #expect(Set(report.testFailures.map(\.name)) == ["\"Display named check\"", "quoteCase(_:)", "other()"], sourceLocation: sourceLocation)
        #expect(report.testFailures.count == 5, sourceLocation: sourceLocation)
        #expect(report.testFailures.allSatisfy { $0.location?.hasPrefix("GizmoTests.swift:") == true }, sourceLocation: sourceLocation)
        #expect(!answer.contains("XCTest"), sourceLocation: sourceLocation)
        #expect(answer.contains("totals: ✘ failed · Swift Testing 3 tests in 0 suites, 3 failing (5 issues), 0 skipped"), sourceLocation: sourceLocation)
    }

    /// The verbose capture: the display-named test, the three located issues of `quoteCase(_:)` and `other()` all reach the answer.
    @Test
    func aDisplayNamedParameterisedTestUnderVerboseLeavesEveryFailureNamed() throws {
        try Self.expectEveryFailureNamed(in: "swift-test-param-display-name-fail-verbose")
    }

    /// The plain capture of the same run gives the same answer.
    @Test
    func theSameRunWithoutVerboseNamesTheSameFailures() throws {
        try Self.expectEveryFailureNamed(in: "swift-test-param-display-name-fail")
    }

    /// A display-named test with no arguments, failing under `--verbose`, is named by its display name alone and counted as failed.
    @Test
    func aDisplayNamedTestUnderVerboseIsNamedByItsDisplayName() {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in [
            "◇ Test run started.",
            "◇ Test \"Plain check\" (aka 'plainCheck()') started.",
            "✘ Test \"Plain check\" (aka 'plainCheck()') recorded an issue at GizmoTests.swift:5:5: Expectation failed: Bool(false)",
            "✘ Test \"Plain check\" (aka 'plainCheck()') failed after 0.001 seconds with 1 issue.",
            "✘ Test run with 1 test in 0 suites failed after 0.001 seconds with 1 issue.",
        ] {
            filter.consume(line: line)
        }
        let report = filter.finish(exitCode: 1)

        #expect(report.testFailures.map(\.name) == ["\"Plain check\""])
        #expect(report.testFailures.first?.location == "GizmoTests.swift:5:5")
        #expect(report.testOutcomes.lastEndings == ["\"Plain check\"": .failed])
    }
}
