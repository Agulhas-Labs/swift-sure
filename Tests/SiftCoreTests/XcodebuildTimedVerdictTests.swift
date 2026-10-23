//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers an `xcodebuild` verdict line that closes on the action's duration, as some Xcode releases print it: `** TEST BUILD SUCCEEDED ** [15.579 sec]`.
///
/// Each log is one of the captured `xcodebuild` transcripts with its closing verdict line swapped for the timed one, so the only difference from the capture is the duration. Before these were read, every such run, pass or fail, answered with no verdict, and a green build was never recorded where the stop gate looks for one.
struct XcodebuildTimedVerdictTests {
    private static let testBuild = ["xcodebuild", "build-for-testing", "-scheme", "Gizmo", "-destination", "id=0000", "-derivedDataPath", "build"]

    /// A timed `build-for-testing` pass answers green with that verdict, exactly as the same log without the duration does.
    @Test
    func aTimedTestBuildPassAnswersAsTheUntimedOneDoes() throws {
        let timedLine = "** TEST BUILD SUCCEEDED ** [15.579 sec]"
        let untimed = try Self.report(Self.log("xcodebuild-build-success", closingOn: "** TEST BUILD SUCCEEDED **"), invokedAs: Self.testBuild, exitCode: 0)
        let timed = try Self.report(Self.log("xcodebuild-build-success", closingOn: timedLine), invokedAs: Self.testBuild, exitCode: 0)
        let verdict = try #require(timed.verdict)

        #expect(verdict.state == .succeeded)
        #expect(verdict.line == timedLine)
        #expect(verdict.answersTheInvokedCommand)
        let answer = Self.answer(timed, exitCode: 0)
        #expect(answer.hasPrefix("✔ xcodebuild\n"))
        #expect(answer.contains(timedLine))
        #expect(answer == Self.answer(untimed, exitCode: 0).replacingOccurrences(of: "** TEST BUILD SUCCEEDED **", with: timedLine))
    }

    /// A timed failing build answers red.
    @Test
    func aTimedBuildFailureAnswersRed() throws {
        let timedLine = "** BUILD FAILED ** [3.2 sec]"
        let report = try Self.report(
            Self.log("xcodebuild-build-failure-dup", closingOn: timedLine),
            invokedAs: ["xcodebuild", "build", "-scheme", "Gizmo"],
            exitCode: 65
        )
        let verdict = try #require(report.verdict)

        #expect(verdict.state == .failed)
        #expect(verdict.line == timedLine)
        #expect(verdict.answersTheInvokedCommand)
        #expect(Self.answer(report, exitCode: 65).hasPrefix("✘ xcodebuild — exit 65\n"))
    }

    /// A timed `xcodebuild test` pass, with a whole number of seconds, answers green.
    @Test
    func aTimedTestPassWithWholeSecondsAnswersGreen() throws {
        let timedLine = "** TEST SUCCEEDED ** [42 sec]"
        let report = try Self.report(
            Self.log("xcodebuild-test-success", closingOn: timedLine),
            invokedAs: ["xcodebuild", "test", "-scheme", "Gizmo"],
            exitCode: 0
        )
        let verdict = try #require(report.verdict)

        #expect(verdict.state == .succeeded)
        #expect(verdict.line == timedLine)
        #expect(verdict.answersTheInvokedCommand)
        #expect(Self.answer(report, exitCode: 0).hasPrefix("✔ xcodebuild\n"))
    }

    /// A timed green build proves its tree, which is what files the record the stop gate reads.
    @Test
    func aTimedGreenBuildIsRecordedAsGreen() throws {
        let report = try Self.report(
            Self.log("xcodebuild-build-success", closingOn: "** TEST BUILD SUCCEEDED ** [15.579 sec]"),
            invokedAs: Self.testBuild,
            exitCode: 0
        )
        let outcome = RunOutcome(
            kind: RunCommandKind.recognize(Self.testBuild),
            logKey: "xcodebuild build-for-testing",
            exitCode: 0,
            report: report,
            log: nil,
            repositoryRoot: nil
        )

        #expect(outcome.provedGreen(testBundles: .undetermined))
    }

    /// A line that merely holds a timed verdict's words, before more text, is no verdict.
    ///
    /// The capture this swaps it into opens on a clean's verdict, which is not the one a build owes, so the run is left with no verdict it answers to.
    @Test
    func aLineQuotingATimedVerdictIsNoVerdict() throws {
        let lines = [
            "note: ** BUILD SUCCEEDED ** [1 sec] was printed by a script",
            "** BUILD SUCCEEDED ** [1 sec] was printed by a script",
        ]
        for line in lines {
            #expect(RunVerdict.state(of: line) == nil)
            let report = try Self.report(Self.log("xcodebuild-build-success", closingOn: line), invokedAs: ["xcodebuild", "build", "-scheme", "Gizmo"], exitCode: 0)
            #expect(!report.summaryLines.contains(line))
            #expect(report.verdict?.line != line)
            #expect(report.verdict?.answersTheInvokedCommand != true)
        }
    }

    /// The capture `name` with its closing `** BUILD SUCCEEDED **`, `** BUILD FAILED **` or `** TEST SUCCEEDED **` line replaced by `line`.
    private static func log(_ name: String, closingOn line: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let capture = try TestSources.runOutput(name)
        let closing = try #require(
            ["** BUILD SUCCEEDED **", "** BUILD FAILED **", "** TEST SUCCEEDED **"].first { capture.contains("\n\($0)\n") },
            sourceLocation: sourceLocation
        )
        return capture.replacingOccurrences(of: "\n\(closing)\n", with: "\n\(line)\n")
    }

    /// The report `swift-sure run` builds from `text` for `arguments`.
    private static func report(_ text: String, invokedAs arguments: [String], exitCode: Int32) -> RunReport {
        var filter = RunOutputFilter(invokedAs: arguments)
        filter.consume(Data(text.utf8))
        return filter.finish(exitCode: exitCode)
    }

    private static func answer(_ report: RunReport, exitCode: Int32) -> String {
        RunReportRenderer(kind: .xcodebuild, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"))
            .render(report, exitCode: exitCode, logURL: URL(fileURLWithPath: "/Users/dev/Gizmo/.swift-sure/runs/run-20260906-194437-1c4de9a2.log"))
    }
}
