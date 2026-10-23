//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Under `--verbose` Swift Testing names a raw-identifier test `"it's param" (aka '`it's param`(x:)')`, an alias holding a `'` of its own, and the answer names it as the plain log does.
struct RunVerboseRawIdentifierTests {
    /// The failing run in `fixture`, read as `swift test` reads it, and its rendered answer.
    private static func realRun(_ fixture: String) throws -> (report: RunReport, answer: String) {
        let report = try TestSources.runReport(fixture, invokedAs: ["swift", "test"], exitCode: 1)
        let answer = RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"))
            .render(report, exitCode: 1, logURL: nil)
        return (report, answer)
    }

    /// The three failing tests are named, each of the four issues located, and the totals read the run's own verdict.
    private static func expectEveryIssueLocated(in fixture: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (report, answer) = try realRun(fixture)

        #expect(report.verdict?.state == .failed, sourceLocation: sourceLocation)
        #expect(Set(report.testFailures.map(\.name)) == ["\"it's param\"", "later(x:)", "other()"], sourceLocation: sourceLocation)
        #expect(report.testFailures.count == 4, sourceLocation: sourceLocation)
        #expect(report.testFailures.allSatisfy { $0.location?.hasPrefix("GizmoTests.swift:") == true }, sourceLocation: sourceLocation)
        #expect(answer.contains("\"it's param\" with x → 1 — GizmoTests.swift:5:5"), sourceLocation: sourceLocation)
        #expect(!answer.contains("failed with no message of its own"), sourceLocation: sourceLocation)
        #expect(answer.contains("totals: ✘ failed · Swift Testing 3 tests in 0 suites, 3 failing (4 issues), 0 skipped"), sourceLocation: sourceLocation)
    }

    /// The two tests a display name and a raw identifier name, each failing once, are named as the plain log names them.
    private static func expectNamedAsPlain(in fixture: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (report, answer) = try realRun(fixture)

        #expect(report.testFailures.map(\.name).sorted() == ["\"Has (aka 'z') inside\"", "\"it's raw\""], sourceLocation: sourceLocation)
        #expect(report.testFailures.allSatisfy { $0.location?.hasPrefix("ExtraTests.swift:") == true }, sourceLocation: sourceLocation)
        #expect(report.testOutcomes.lastEndings == ["\"Has (aka 'z') inside\"": .failed, "\"it's raw\"": .failed], sourceLocation: sourceLocation)
        #expect(answer.contains("totals: ✘ failed · Swift Testing 2 tests in 0 suites, 2 failing, 0 skipped"), sourceLocation: sourceLocation)
    }

    /// The verbose capture: no case opening of the raw-identifier test is left unclosed to swallow another test's issue.
    @Test
    func aRawIdentifierParameterisedTestUnderVerboseLeavesEveryIssueLocated() throws {
        try Self.expectEveryIssueLocated(in: "swift-test-param-raw-identifier-fail-verbose")
    }

    /// The plain capture of the same run gives the same answer.
    @Test
    func theSameRawIdentifierRunWithoutVerboseLocatesTheSameIssues() throws {
        try Self.expectEveryIssueLocated(in: "swift-test-param-raw-identifier-fail")
    }

    /// Under `--verbose` a raw-identifier test with no arguments is named without its alias, and a display name holding ` (aka 'z')` keeps it.
    @Test
    func aRawIdentifierTestUnderVerboseIsNamedAsThePlainLogNamesIt() throws {
        try Self.expectNamedAsPlain(in: "swift-test-raw-identifier-fail-verbose")
    }

    /// The plain capture names both tests the same way.
    @Test
    func theRawIdentifierTestWithoutVerboseIsNamedTheSame() throws {
        try Self.expectNamedAsPlain(in: "swift-test-raw-identifier-fail")
    }
}
