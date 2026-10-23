//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the live tally against the finished report: however the output was cut into chunks, and whichever capture it read, the live count ends where the report's does.
struct RunLiveTallyParityTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    /// The state a tally ends in when it is handed `chunks` one after another and then finished.
    private static func state(fedInChunks chunks: [Data]) -> RunLiveState {
        var tally = RunLiveTally(startedAt: start)
        for chunk in chunks {
            tally.consume(chunk, now: start)
        }
        _ = tally.finish(now: start)
        return tally.state
    }

    /// A chunk boundary at any byte, inside a line, inside a multi-byte status glyph or a thin space, changes nothing: every split of the capture ends in the state the whole capture does.
    @Test(arguments: ["swift-test-fail", "swift-test-colored-warning-and-failure"])
    func aChunkBoundaryAtAnyByteChangesNothing(capture: String) throws {
        let bytes = try TestSources.runOutputData(capture, extension: "txt")
        let whole = Self.state(fedInChunks: [bytes])

        #expect(whole.tests.finished > 0)
        for offset in 0 ... bytes.count {
            let split = Self.state(fedInChunks: [bytes.prefix(offset), bytes.dropFirst(offset)].map { Data($0) })
            #expect(split == whole, "split at byte \(offset)")
        }
    }

    /// The live count of tests, errors and warnings equals the finished report's: its tests as ``RunTestOutcomes`` last saw each end, its errors and warnings as its diagnostics listed them.
    @Test(arguments: [
        ("swift-test-fail", ["swift", "test"]),
        ("swift-test-pass", ["swift", "test"]),
        ("swift-test-mixed-xctest-failure", ["swift", "test"]),
        ("swift-test-colored-warning-and-failure", ["swift", "test"]),
        ("swift-test-display-name", ["swift", "test"]),
        ("swift-build-success", ["swift", "build"]),
        ("xcodebuild-test-failure", ["xcodebuild", "test"]),
        ("xcodebuild-test-success", ["xcodebuild", "test"]),
        ("xcodebuild-retry-iterations", ["xcodebuild", "test"]),
    ])
    func theLiveCountEndsWhereTheReportsDoes(capture: String, invocation: [String]) throws {
        let bytes = try TestSources.runOutputData(capture, extension: "txt")
        let live = Self.state(fedInChunks: [bytes])
        let report = try TestSources.runReport(capture, invokedAs: invocation)
        let endings = report.testOutcomes.lastEndings.values

        #expect(live.tests.passed == endings.count { $0 == .passed })
        #expect(live.tests.failed == endings.count { $0 == .failed })
        #expect(live.tests.skipped == endings.count { $0 == .skipped })
        #expect(live.errors == report.errors.count)
        #expect(live.warnings == report.warnings.count)
    }

    /// Where no test repeats, the live count is also the tools' own: XCTest's outermost `Executed …` counter plus Swift Testing's run tally.
    @Test(arguments: [("swift-test-fail", 5), ("swift-test-pass", 4), ("xcodebuild-test-failure", 1)])
    func theLiveCountIsTheToolsOwnClosingCount(capture: String, closing: Int) throws {
        let bytes = try TestSources.runOutputData(capture, extension: "txt")
        let lines = try TestSources.runOutput(capture).components(separatedBy: "\n")
        let counters = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("Executed ") }
        let executed = counters.last.flatMap { RunOutputFilter.ExecutedCounts(line: $0)?.tests } ?? 0
        let tallied = try TestSources.runReport(capture, invokedAs: ["swift", "test"]).tally?.tests ?? 0

        #expect(executed + tallied == closing)
        #expect(Self.state(fedInChunks: [bytes]).tests.finished == closing)
    }

    /// A test's ending spliced apart by its own output counts live as the finished report counts it, and as the framework printed it, however the bytes arrive.
    @Test(arguments: splicedLogs)
    func aSplicedEndingCountsLiveAsTheReportCountsIt(log: SplicedLog) {
        var filter = RunOutputFilter(invokedAs: ["xcodebuild", "test", "-scheme", "Gizmo-Package"])
        for line in log.lines {
            filter.consume(line: line)
        }
        let endings = filter.finish(exitCode: 0).testOutcomes.lastEndings.values
        let bytes = Data(log.lines.map { $0 + "\n" }.joined().utf8)

        for live in [Self.state(fedInChunks: [bytes]), Self.state(fedInChunks: bytes.map { Data([$0]) })] {
            #expect(live.tests.passed == endings.count { $0 == .passed }, "\(log.name)")
            #expect(live.tests.failed == endings.count { $0 == .failed }, "\(log.name)")
            #expect(live.tests == RunLiveState.Tests(passed: log.passed, failed: log.failed), "\(log.name)")
        }
    }
}

extension RunLiveTallyParityTests {
    /// A console log with a spliced ending in it, and the tests the framework says passed and failed.
    struct SplicedLog: Sendable, CustomTestStringConvertible {
        let name: String
        let lines: [String]
        let passed: Int
        let failed: Int

        var testDescription: String {
            name
        }
    }

    /// A line from another stream, spliced in whole.
    private static var logLine: String {
        "2026-10-12 12:59:21.353130+0100 xctest[61:55] [Depot] Reloading the catalogue failed: error 0.)"
    }

    /// The same, closing on a pass's words of its own.
    private static var passingLogLine: String {
        "2026-10-12 12:59:21.353 xctest[61:55] [Depot] subtask passed after 3 seconds."
    }

    /// Every spliced shape the finished report reads, with a start line in front of each.
    static let splicedLogs = [
        SplicedLog(name: "closing a pass", lines: ["✔ Test countIsOne() Barrierpassed after 15.5 seconds."], passed: 1, failed: 0),
        SplicedLog(name: "pass on the next line", lines: ["✔ Test countIsOne() " + logLine, "passed after 198.5 seconds."], passed: 1, failed: 0),
        SplicedLog(name: "ending two lines later", lines: ["✔ Test countIsOne() " + logLine, logLine, "passed after 1 seconds."], passed: 0, failed: 0),
        SplicedLog(name: "failure under a pass", lines: ["✘ Test countIsOne() " + passingLogLine, "failed after 4 seconds with 1 issue."], passed: 0, failed: 1),
        SplicedLog(name: "plain pass after a failure", lines: ["✘ Test countIsOne() Barrierfailed after 1 seconds with 1 issue.", "passed after 2 seconds."], passed: 0, failed: 1),
        SplicedLog(
            name: "issue on the next line",
            lines: ["✘ Test countIsOne() " + passingLogLine, "recorded an issue at Depot.swift:5:5: Expectation failed", "✘ Test countIsOne() failed after 4 seconds with 1 issue."],
            passed: 0,
            failed: 1
        ),
        SplicedLog(
            name: "known issue on the next line",
            lines: ["━ Test countIsOne() " + passingLogLine, "recorded a known issue at Depot.swift:5:5: Expectation failed", "━ Test countIsOne() passed after 4 seconds with 1 known issue."],
            passed: 1,
            failed: 0
        ),
    ].map { SplicedLog(name: $0.name, lines: ["◇ Test countIsOne() started."] + $0.lines, passed: $0.passed, failed: $0.failed) }
}
