//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A shard ended by a signal SwiftSure did not send is named as such, in its notes and on its loss line, and one SwiftSure ended is not.
@Suite(.temporaryDirectories)
struct ShardOutsideSignalTests {
    private static let alpha = ((try? PackageShardPlanner.listed("GizmoTests.AlphaTests/testOne()")) ?? [])[0]

    private static func reconcile(_ outcome: ShardOutcome) -> (notes: [String], answer: String) {
        let plan = PackageShardPlanner.plan(tests: [alpha], shards: 1) { _ in nil }
        let reconciliation = ShardMerge.reconcile(plan: plan, outcomes: [outcome])
        return (reconciliation.notes, ShardAnswerRenderer(swiftPackage: true).render(reconciliation, plan: plan))
    }

    @Test
    func aShardASignalFromOutsideEndedIsNamedWithTheSignalAndAsNotSentBySift() {
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGTERM, wallSeconds: 447, logPath: "/runs/kept.log")
        outcome.terminatingSignal = SIGTERM

        let (notes, answer) = Self.reconcile(outcome)

        #expect(notes.contains("shard 1 was ended after 447s by SIGTERM, which swift-sure did not send — its unreported tests are missing"), "\(notes)")
        #expect(answer.contains("shard 1 lost 1 of 1: exit 143 (ended by SIGTERM, which swift-sure did not send)"), "\(answer)")
    }

    @Test
    func aSignalsExitCodeWithNoSignalIsNamedAsACodeWithNothingFromSift() {
        let outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGKILL, wallSeconds: 12, logPath: "/runs/kept.log")

        let (notes, _) = Self.reconcile(outcome)

        #expect(notes.contains("shard 1 exited 137 (128 + SIGKILL) after 12s, with no bound, stop or interruption from swift-sure — its unreported tests are missing"), "\(notes)")
    }

    @Test
    func aShardSiftEndedAtABoundIsNotNamedAsSignalledFromOutside() {
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGTERM, wallSeconds: 400, logPath: "")
        outcome.terminatingSignal = SIGTERM
        outcome.ending = ShardOutcome.Ending(bound: .silence(300), keptOwnResult: false)

        let (notes, answer) = Self.reconcile(outcome)

        #expect(!notes.contains { $0.contains("swift-sure did not send") || $0.contains("from swift-sure") }, "\(notes)")
        #expect(answer.contains("exit 143 (ended by SIGTERM)"), "\(answer)")
    }

    @Test
    func theWaitReportsTheSignalThatEndedAChildAndNoneForOneThatExited() throws {
        let children = SetAsideChildren()
        let null = open("/dev/null", O_RDWR | O_CLOEXEC)
        defer { close(null) }
        let streams = SetAsideChildren.Streams(input: null, output: null, error: null)
        let directory = try TemporaryDirectory.make("outside-signal")
        let signalled = try children.spawn("/bin/sh", ["-c", "kill -TERM $$"], in: directory, environment: [:], streams: streams)
        let exited = try children.spawn("/bin/sh", ["-c", "exit 143"], in: directory, environment: [:], streams: streams)

        let bySignal = SetAsideChildren.termination(waitingFor: signalled)
        let byExit = SetAsideChildren.termination(waitingFor: exited)
        children.endAll()

        #expect(bySignal.exitCode == 143 && bySignal.signal == SIGTERM)
        #expect(byExit.exitCode == 143 && byExit.signal == nil)
    }

    @Test
    func aShardTheStallWatchStoppedIsNotNamedAsSignalledFromOutside() {
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGTERM, wallSeconds: 90, logPath: "/runs/kept.log")
        outcome.terminatingSignal = SIGTERM
        outcome.stoppedTest = RunStoppedTest(quiet: 30, crash: nil)

        let (notes, answer) = Self.reconcile(outcome)

        #expect(!notes.contains { $0.contains("swift-sure did not send") || $0.contains("from swift-sure") }, "\(notes)")
        #expect(!answer.contains("swift-sure did not send"), "\(answer)")
    }

    @Test
    func aShardThatNeverStartedIsNotNamedAsSignalledFromOutside() {
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGTERM, wallSeconds: 0, logPath: "")
        outcome.launchFailure = "could not start /usr/bin/env: No such file or directory"

        let (notes, answer) = Self.reconcile(outcome)

        #expect(!notes.contains { $0.contains("swift-sure did not send") || $0.contains("from swift-sure") }, "\(notes)")
        #expect(!answer.contains("swift-sure did not send"), "\(answer)")
    }

    @Test
    func aShardTheInterruptionEndedIsNotNamedAsSignalledFromOutside() {
        var outcome = ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGTERM, wallSeconds: 12, logPath: "/runs/kept.log")
        outcome.terminatingSignal = SIGTERM
        outcome.endedByInterruption = true

        let (notes, answer) = Self.reconcile(outcome)

        #expect(!notes.contains { $0.contains("swift-sure did not send") || $0.contains("from swift-sure") }, "\(notes)")
        #expect(!answer.contains("swift-sure did not send"), "\(answer)")
    }
}
