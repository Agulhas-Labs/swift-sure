//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how a shard's run is ended: after a silence, which is what a stuck shard does, never merely for running long while it still prints, and with a note naming whatever ended it — the stall watch included.
///
/// The clock is injected, because these windows are minutes long and a loaded machine moves a real one. Each launch moves the clock and then waits until the supervisor has looked at it, so every moment a pin speaks of is one the supervisor saw.
@Suite(.temporaryDirectories)
struct ShardProgressBoundTests {
    /// A shard printing every ten seconds runs past three times its prediction and past the old ten-minute bound without being ended: a wall clock cannot tell slow from stuck, and a working shard ended there costs the tests it had left.
    @Test(.timeLimit(.minutes(1)))
    func aShardThatKeepsReportingPastTheOldBoundIsNotEnded() throws {
        let directory = try TemporaryDirectory.make("shard-progress")
        let clock = Clock()
        let predicted: Double = 150
        let runner = ShardRunner(
            workingDirectory: directory,
            repositoryRoot: nil,
            children: SetAsideChildren(),
            launch: { assignment, _, heard in
                // Seventy reports ten seconds apart: 700 s, past 3 × 150 s and past 600 s.
                for step in 1 ... 70 {
                    clock.advance(10)
                    heard()
                    if Double(step) * 10 > 3 * predicted {
                        clock.awaitLooks(1)
                    }
                }
                return Self.outcome(shard: assignment.index)
            },
            now: { clock.now },
            patience: 0.1
        )

        let outcomes = runner.run([ShardRunner.Assignment(index: 1, argv: ["/usr/bin/true"], bound: ShardRunner.bound(forPredicted: predicted))])

        #expect(!outcomes[0].timedOut)
        #expect(outcomes[0].logPath == "/tmp/shard-1.log")
    }

    /// A shard that prints nothing for the progress bound is ended, the silence counted from the last output rather than from the start, and the note names that bound rather than a wall clock.
    @Test(.timeLimit(.minutes(1)))
    func aShardSilentForTheProgressBoundIsEnded() throws {
        let directory = try TemporaryDirectory.make("shard-progress")
        let clock = Clock()
        let stuck = DispatchSemaphore(value: 0)
        defer { stuck.signal() }
        let runner = ShardRunner(
            workingDirectory: directory,
            repositoryRoot: nil,
            children: SetAsideChildren(),
            launch: { assignment, _, heard in
                clock.advance(100)
                heard()
                // 299 s quiet is not yet the bound; one second more is.
                clock.advance(299)
                clock.awaitLooks(2)
                clock.advance(1)
                _ = stuck.wait(timeout: .now() + 5)
                return Self.outcome(shard: assignment.index)
            },
            now: { clock.now },
            patience: 0.1
        )

        let outcomes = runner.run([ShardRunner.Assignment(index: 1, argv: ["/usr/bin/true"], bound: ShardRunner.bound(forPredicted: 10))])

        #expect(outcomes[0].ending == ShardOutcome.Ending(bound: .silence(ShardRunner.silenceBound), keptOwnResult: false))
        let notes = ShardMerge.reconcile(plan: Self.plan, outcomes: outcomes).notes
        #expect(notes.contains("shard 1 was ended after 400s with no output for 300s and no result — its unreported tests are missing"))
    }

    /// A shard whose `swift test` the stall watch stopped says so: the stop ends the shard with the SIGTERM's code over a log that just stops, and without the note the tests after the cut read as crashes nobody explained.
    @Test
    func aShardTheStallWatchStoppedIsNamedAsStopped() {
        let run = RunOutcome(
            kind: .swiftTest,
            logKey: "swift test",
            exitCode: 128 + SIGTERM,
            report: nil,
            log: nil,
            repositoryRoot: nil,
            stoppedTest: RunStoppedTest(quiet: 30, crash: nil)
        )

        let merged = ShardMerge.reconcile(plan: Self.plan, outcomes: [ShardRunner.shard(from: run, wallSeconds: 447.2)])

        #expect(merged.notes.contains("shard 1 was stopped after 447.2s with no output for 30s and no live test process — its unreported tests are missing"))
    }

    private static var plan: ShardPlan {
        ShardPlan(
            shards: [ShardPlan.Shard(index: 1, tests: [], predictedSeconds: 10)],
            requestedShards: 1,
            overheadSeconds: 0,
            estimatedTests: 0,
            estimatedSeconds: 1,
            displayNames: [:],
            lowering: nil
        )
    }

    private static func outcome(shard index: Int) -> ShardOutcome {
        ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 0, wallSeconds: 1, logPath: "/tmp/shard-\(index).log")
    }
}

private extension ShardProgressBoundTests {
    /// A clock the launch moves by hand, counting every time it is read, so a launch can wait for the supervisor to have looked.
    final class Clock: @unchecked Sendable {
        private let gate = NSCondition()
        private var current = Date(timeIntervalSinceReferenceDate: 0)
        private var reads = 0

        var now: Date {
            gate.withLock {
                reads += 1
                gate.broadcast()
                return current
            }
        }

        func advance(_ seconds: TimeInterval) {
            gate.withLock { current += seconds }
        }

        /// Waits until the clock has been read `count` more times, or two seconds have passed: the supervisor reads it once a look.
        func awaitLooks(_ count: Int) {
            gate.withLock {
                let target = reads + count
                let deadline = Date().addingTimeInterval(2)
                while reads < target, gate.wait(until: deadline) {}
            }
        }
    }
}
