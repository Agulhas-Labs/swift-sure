//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A SwiftPM package's shards: suites charged their tests' summed time, and a shard that lost tests diagnosed from what it left.
@Suite(.temporaryDirectories)
struct PackageShardCostAndLossTests {
    private static let alpha = test("LibTests.AlphaTests/testOne()")
    private static let beta = test("LibTests.BetaTests/testTwo()")

    /// The identifier `swift test list` would give the line `listed`.
    private static func test(_ listed: String) -> TestIdentifier {
        ((try? PackageShardPlanner.listed(listed)) ?? []).first ?? ((try? PackageShardPlanner.listed("Invalid.Invalid/invalid()")) ?? [])[0]
    }

    @Test func theEventStreamOptionIsTheOneThisSwiftTestNames() {
        #expect(EventStreamDirectory.outputOption(inHelp: "  --xunit-output <xunit-output>\n  --event-stream-output-path <event-stream-output-path>\n") == "--event-stream-output-path")
        #expect(EventStreamDirectory.outputOption(inHelp: "  --experimental-event-stream-output <path>\n") == "--experimental-event-stream-output")
        #expect(EventStreamDirectory.outputOption(inHelp: "  --xunit-output <xunit-output>\n") == nil)
    }

    @Test func aSuiteIsChargedItsTestsSummedTime() {
        let tests = (1 ... 4).map { Self.test("LibTests.AlphaTests/test\($0)()") } + [Self.beta]
        let summed = PackageShardPlanner.plan(tests: tests, shards: 2) { _ in 3 }

        #expect(summed.shards.map(\.predictedSeconds).sorted() == [5, 14])
    }

    @Test func aShardThatLostTestsNamesItsExitItsClosingLineAndItsKeptLog() throws {
        let plan = PackageShardPlanner.plan(tests: [Self.alpha, Self.beta], shards: 2) { _ in nil }
        let outcomes = plan.shards.map { shard in
            var read = RunTestOutcomes()
            guard shard.tests == [Self.alpha] else {
                return ShardOutcome(outcomes: read, exitCode: 139, wallSeconds: 1, logPath: "/runs/kept-run-b.log")
            }
            read.read("✔ Test testOne() passed after 0.1 seconds.")
            var outcome = ShardOutcome(outcomes: read, exitCode: 0, wallSeconds: 1, logPath: "/runs/run-a.log")
            outcome.closedWithRunSummary = true
            return outcome
        }
        let lost = try #require(plan.shards.first { $0.tests == [Self.beta] }).index
        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: outcomes)

        let answer = ShardAnswerRenderer(swiftPackage: true).render(reconciliation, plan: plan)
        let simulator = ShardAnswerRenderer().render(reconciliation, plan: plan)

        #expect(answer.contains("shard \(lost) lost 1 of 1: exit 139 (128 + signal 11, \(String(cString: strsignal(11))), if it was signalled, which swift-sure did not send) · no Swift Testing `Test run with …` line in its log · log kept at /runs/kept-run-b.log"))
        #expect(!answer.contains("lost 0"))
        #expect(!simulator.contains(" lost 1 of 1"))
    }

    @Test func aKeptLogOutlivesThePruningOfTheRunsAfterIt() throws {
        let root = try TemporaryDirectory.make("kept-log")
        let temporary = try TemporaryDirectory.make("kept-log-fallback")
        let first = try #require(RunLog.open(inDirectory: root, fallingBackTo: temporary))
        first.append(Data("lost".utf8))
        first.close()

        let kept = try #require(RunLog.keep(first.url.path))
        for _ in 0 ..< RunLog.keptLogs + 1 {
            try #require(RunLog.open(inDirectory: root, fallingBackTo: temporary)).close()
        }

        #expect(FileManager.default.contents(atPath: kept) == Data("lost".utf8))
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(RunLog.keep(root.appendingPathComponent("unrelated.log").path) == nil)
    }
}
