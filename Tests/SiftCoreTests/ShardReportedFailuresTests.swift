//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers what a sharded reconciliation says failed in it: the names a wrapped run would give, `[]` for a run that accounted for every test and lost none, and `nil` for one that cannot say.
struct ShardReportedFailuresTests {
    private static func test(_ listed: String) -> TestIdentifier {
        ((try? PackageShardPlanner.listed(listed)) ?? []).first ?? ((try? PackageShardPlanner.listed("Invalid.Invalid/invalid()")) ?? [])[0]
    }

    private static func streamID(_ listed: String) -> String {
        "\(listed)/AlphaTests.swift:3:6".replacingOccurrences(of: "/", with: #"\/"#)
    }

    private static func event(_ kind: String, _ listed: String, at instant: Double, issue: String? = nil) -> String {
        let issueField = issue.map { #""issue":\#($0),"# } ?? ""
        return #"{"kind":"event","payload":{\#(issueField)"instant":{"absolute":\#(instant),"since1970":0},"iteration":1,"kind":"\#(kind)","messages":[],"testID":"\#(streamID(listed))"},"version":"6.4.0"}"#
    }

    private static func failed(_ listed: String) -> [String] {
        [
            #"{"kind":"test","payload":{"id":"\#(streamID(listed))","isParameterized":false,"kind":"function","name":"x"},"version":"6.4.0"}"#,
            event("testStarted", listed, at: 1),
            event("issueRecorded", listed, at: 1.5, issue: #"{"isFailure":true,"isKnown":false,"severity":"error"}"#),
            event("testEnded", listed, at: 2),
        ]
    }

    /// A failing issue for a test that never started, which is how a thrown condition reads.
    private static func failedBeforeStarting(_ listed: String) -> [String] {
        [
            #"{"kind":"test","payload":{"id":"\#(streamID(listed))","isParameterized":false,"kind":"function","name":"x"},"version":"6.4.0"}"#,
            event("issueRecorded", listed, at: 1.5, issue: #"{"isFailure":true,"isKnown":false,"severity":"error"}"#),
        ]
    }

    private static func plan(_ shards: [[TestIdentifier]]) -> ShardPlan {
        ShardPlan(
            shards: shards.enumerated().map { index, tests in
                ShardPlan.Shard(index: index + 1, tests: tests, predictedSeconds: 20 + Double(tests.count))
            },
            requestedShards: shards.count,
            overheadSeconds: 20,
            estimatedTests: 0,
            estimatedSeconds: 1,
            displayNames: [:],
            lowering: nil
        )
    }

    private static func streamed(_ lines: [String], exitCode: Int32 = 0) -> ShardOutcome {
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: exitCode, wallSeconds: 2, logPath: "log")
        outcome.eventStream = ShardEventStream.read(lines.joined(separator: "\n"))
        return outcome
    }

    private static func passed(_ listed: String) -> [String] {
        [
            #"{"kind":"test","payload":{"id":"\#(streamID(listed))","isParameterized":false,"kind":"function","name":"x"},"version":"6.4.0"}"#,
            event("testStarted", listed, at: 1),
            event("testEnded", listed, at: 2),
        ]
    }

    /// A failed test is named as its record names it, and one no record names as the answer's own list names it, each once.
    @Test func aCompleteRedRunNamesEachFailedTestOnce() {
        let recorded = Self.test("LibTests.AlphaTests/one()")
        let lost = Self.test("LibTests.AlphaTests/two()")
        let plan = PackageShardPlanner.plan(tests: [recorded, lost], shards: 1) { _ in nil }
        let record = RunTestFailure(name: "one()", location: "AlphaTests.swift:4", message: "Expectation failed: 1 == 2")
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 1, wallSeconds: 2, logPath: "log", failures: [record])
        outcome.eventStream = ShardEventStream.read((Self.failed("LibTests.AlphaTests/one()") + Self.failed("LibTests.AlphaTests/two()")).joined(separator: "\n"))

        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [outcome])

        #expect(reconciliation.reportedTestFailures == ["one()", "two()"])
    }

    /// Every test ended and none failed: the run speaks, and says nothing failed.
    @Test func aCompleteGreenRunAnswersNoFailures() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let plan = PackageShardPlanner.plan(tests: [one], shards: 1) { _ in nil }
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 0, wallSeconds: 2, logPath: "log")
        outcome.eventStream = ShardEventStream.read(Self.passed("LibTests.AlphaTests/one()").joined(separator: "\n"))

        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [outcome])

        #expect(reconciliation.isGreen)
        #expect(reconciliation.reportedTestFailures == [])
    }

    /// A test the plan named and no log ended is not accounted for, so the run cannot say what failed in it.
    @Test func aMissingTestAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let two = Self.test("LibTests.AlphaTests/two()")
        let plan = PackageShardPlanner.plan(tests: [one, two], shards: 1) { _ in nil }
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 1, wallSeconds: 2, logPath: "log")
        outcome.eventStream = ShardEventStream.read(Self.failed("LibTests.AlphaTests/one()").joined(separator: "\n"))

        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [outcome])

        #expect(reconciliation.counts.missing == 1)
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A shard ended at its bound is a shard that could be hiding a failure, even where every test it was given reported.
    @Test func aShardEndedAtItsBoundAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let plan = PackageShardPlanner.plan(tests: [one], shards: 1) { _ in nil }
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 137, wallSeconds: 612, logPath: "log")
        outcome.eventStream = ShardEventStream.read(Self.failed("LibTests.AlphaTests/one()").joined(separator: "\n"))
        outcome.ending = ShardOutcome.Ending(bound: .ceiling(612), keptOwnResult: false)

        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [outcome])

        #expect(reconciliation.shards.first?.timedOut == true)
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A shard that exited non-zero with no test failed crashed rather than failed a test, so it cannot answer `[]`.
    @Test func aNonZeroExitWithNoFailedTestAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let plan = PackageShardPlanner.plan(tests: [one], shards: 1) { _ in nil }
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 65, wallSeconds: 2, logPath: "log")
        outcome.eventStream = ShardEventStream.read(Self.passed("LibTests.AlphaTests/one()").joined(separator: "\n"))

        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [outcome])

        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A failed test no record names, and one that failed before starting, are filed under the name the console prints, not the enumerated identifier, so a wrapped run and a sharded one name one test once.
    @Test func swiftTestingFailuresAreFiledUnderTheirConsoleSpelling() {
        let lost = Self.test("LibTests.AlphaTests/two()")
        let thrown = Self.test("LibTests.BetaTests/seven()")
        let plan = Self.plan([[lost, thrown]])
        let outcome = Self.streamed(Self.failed("LibTests.AlphaTests/two()") + Self.failedBeforeStarting("LibTests.BetaTests/seven()"), exitCode: 1)

        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [outcome])

        #expect(reconciliation.failed == [lost, thrown])
        #expect(reconciliation.reportedTestFailures == ["seven()", "two()"])
    }

    /// An XCTest failure whose console record was lost is filed as the console spells an XCTest case.
    @Test func anXCTestFailureWithNoRecordIsFiledUnderItsConsoleSpelling() {
        let lost = Self.test("LibTests.BetaTests/testAddition()")
        var outcomes = RunTestOutcomes()
        for line in [
            "Test Case '-[LibTests.BetaTests testAddition]' started.",
            "Test Case '-[LibTests.BetaTests testAddition]' failed (0.100 seconds).",
        ] {
            outcomes.read(line)
        }
        let outcome = ShardOutcome(outcomes: outcomes, exitCode: 1, wallSeconds: 2, logPath: "log")

        let reconciliation = ShardMerge.reconcile(plan: Self.plan([[lost]]), outcomes: [outcome])

        #expect(reconciliation.failed == [lost])
        #expect(reconciliation.reportedTestFailures == ["-[LibTests.BetaTests testAddition]"])
    }

    /// One shard's failed test does not excuse another shard's crash.
    @Test func aCrashedShardAnswersNilWhateverAnotherShardFailed() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let two = Self.test("LibTests.AlphaTests/two()")
        let outcomes = [
            Self.streamed(Self.failed("LibTests.AlphaTests/one()"), exitCode: 1),
            Self.streamed(Self.passed("LibTests.AlphaTests/two()"), exitCode: 65),
        ]

        let reconciliation = ShardMerge.reconcile(plan: Self.plan([[one], [two]]), outcomes: outcomes)

        #expect(reconciliation.failed == [one])
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A test two shards both ended is not accounted for once.
    @Test func aDuplicatedTestAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let two = Self.test("LibTests.AlphaTests/two()")
        let outcomes = [
            Self.streamed(Self.passed("LibTests.AlphaTests/one()") + Self.passed("LibTests.AlphaTests/two()")),
            Self.streamed(Self.passed("LibTests.AlphaTests/two()")),
        ]

        let reconciliation = ShardMerge.reconcile(plan: Self.plan([[one], [two]]), outcomes: outcomes)

        #expect(reconciliation.counts.duplicated > 0)
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A group the console could only reconcile by count, and came up short on, cannot name what is missing.
    @Test func aShortfallAnswersNil() {
        let first = Self.test("LibTests.AlphaTests/same()")
        let second = Self.test("LibTests.BetaTests/same()")
        var outcomes = RunTestOutcomes()
        for line in ["Test same() started.", "Test same() passed after 0.001 seconds."] {
            outcomes.read(line)
        }
        let outcome = ShardOutcome(outcomes: outcomes, exitCode: 0, wallSeconds: 2, logPath: "log")

        let merged = ShardMerge.reconcile(plan: Self.plan([[first, second]]), outcomes: [outcome])
        // The shortfall alone, with no count of anything missing beside it.
        let reconciliation = ShardReconciliation(
            counts: ShardReconciliation.Counts(expected: 2, ran: 2, passed: 2, failed: 0, skipped: 0, missing: 0, duplicated: 0),
            shards: merged.shards,
            missing: [],
            shortfalls: merged.shortfalls,
            duplicated: [],
            failed: [],
            timings: [],
            failures: [],
            notes: []
        )

        #expect(!merged.shortfalls.isEmpty)
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A result the plan has no shard for is one nothing read.
    @Test func aResultOutsideThePlanAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let outcomes = [
            Self.streamed(Self.passed("LibTests.AlphaTests/one()")),
            Self.streamed([]),
        ]

        let reconciliation = ShardMerge.reconcile(plan: Self.plan([[one]]), outcomes: outcomes)

        #expect(reconciliation.resultsOutsideThePlan > 0)
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A test a stream ended that the listing never named ran with no shard owing it.
    @Test func anUnlistedTestAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        let outcome = Self.streamed(Self.passed("LibTests.AlphaTests/one()") + Self.passed("LibTests.AlphaTests/stray()"))

        let reconciliation = ShardMerge.reconcile(plan: Self.plan([[one]]), outcomes: [outcome])

        #expect(!reconciliation.unlisted.isEmpty)
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A test the index declares that the listing lost and no stream ended is a test nothing ran.
    @Test func aNeverListedTestAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        var plan = Self.plan([[one]])
        plan.neverListed = [Self.test("LibTests.AlphaTests/lost()")]

        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [Self.streamed(Self.passed("LibTests.AlphaTests/one()"))])

        #expect(!reconciliation.neverListed.isEmpty)
        #expect(reconciliation.reportedTestFailures == nil)
    }

    /// A shard killed by a signal could be hiding a failure, even where it exited 0 and every test reported.
    @Test func aShardKilledBySignalAnswersNil() {
        let one = Self.test("LibTests.AlphaTests/one()")
        var outcome = Self.streamed(Self.passed("LibTests.AlphaTests/one()"))
        outcome.terminatingSignal = 15

        let reconciliation = ShardMerge.reconcile(plan: Self.plan([[one]]), outcomes: [outcome])

        #expect(reconciliation.shards.first?.terminatingSignal == 15)
        #expect(reconciliation.reportedTestFailures == nil)
    }
}
