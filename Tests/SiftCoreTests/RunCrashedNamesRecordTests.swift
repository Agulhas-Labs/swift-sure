//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A run whose test process crashed files the tests the crash left unfinished as `crashed`, beside no `failed`: they are suspects, never failures.
@Suite(.temporaryDirectories)
struct RunCrashedNamesRecordTests {
    @Test
    func aCrashedRunFilesItsUnfinishedTestsAndNoFailures() throws {
        let report = try TestSources.runReport("swift-test-crash-xc", invokedAs: ["swift", "test", "--filter", "testStacks", "--filter", "testBuckles", "--filter", "testLoads", "--filter", "loads"], exitCode: 1)
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: 1, report: report, log: nil, repositoryRoot: nil)
        let unfinished = try #require(report.testCrash?.unfinished)
        #expect(!unfinished.isEmpty)

        let line = try Self.filed(RunUsageLog.Answer(report: report, lines: 12, failedTests: outcome.reportedTestFailures, crashedTests: outcome.crashedTests))

        #expect(line["crashed"] as? [String] == Set(unfinished).sorted())
        #expect(line["crashed_total"] as? Int == Set(unfinished).count)
        #expect(line["failed"] == nil)
        #expect(line["failed_total"] == nil)
    }

    @Test
    func crashedNamesAreClippedAndCappedWithTheDistinctCountBeside() throws {
        var names = (0 ..< 50).map { "Gizmo/Depot/restock\($0)()" }
        names.append("Gizmo/Depot/" + String(repeating: "x", count: 130))

        let line = try Self.filed(RunUsageLog.Answer(crashedTests: names))

        let kept = try #require(line["crashed"] as? [String])

        #expect(kept.count == RunUsageLog.failedTestCap)
        #expect(kept.allSatisfy { $0.count <= RunUsageLog.testNameCap + 1 })
        #expect(line["crashed_total"] as? Int == 51)
    }

    @Test
    func aRunThatDidNotCrashWritesNeither() throws {
        let line = try Self.filed(RunUsageLog.Answer(failedTests: []))

        #expect(line["crashed"] == nil)
        #expect(line["crashed_total"] == nil)
    }

    @Test
    func aTestCrashThatLeftNothingUnfinishedWritesNeitherCrashedField() throws {
        let report = RunReport(errors: [], warnings: [], testFailures: [], summaryLines: [], contract: .runTally, verdict: nil, tally: nil, totalLines: 10, testCrash: RunTestCrash())
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: 0, report: report, log: nil, repositoryRoot: nil)
        #expect(report.testCrash?.unfinished.isEmpty == true)

        let line = try Self.filed(RunUsageLog.Answer(crashedTests: outcome.crashedTests))

        #expect(outcome.crashedTests == nil)
        #expect(line["crashed"] == nil)
        #expect(line["crashed_total"] == nil)
    }

    private static func filed(_ answer: RunUsageLog.Answer, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let file = try TemporaryDirectory.make("run-log").appendingPathComponent("run.jsonl")
        RunUsageLog(fileURL: file).record(logKey: "swift test", exitCode: 1, answer: answer, repositoryRoot: nil, milliseconds: 10)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1, sourceLocation: sourceLocation)
        return try #require(try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any], sourceLocation: sourceLocation)
    }
}
