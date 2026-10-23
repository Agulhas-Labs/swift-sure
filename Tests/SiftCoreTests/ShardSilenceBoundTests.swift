//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how long a shard may print nothing: three times its longest predicted test where that is over the floor, and that the live launcher reports every chunk it reads, stderr included.
///
/// The supervisor's clock is injected, because these windows are minutes long and a loaded machine moves a real one.
@Suite(.temporaryDirectories)
struct ShardSilenceBoundTests {
    @Test
    func theSilenceBoundIsThreeTimesTheLongestPredictedTestNeverUnderTheFloor() {
        #expect(ShardRunner.silenceBound(forLongestTest: 0) == 300)
        #expect(ShardRunner.silenceBound(forLongestTest: 3.6) == 300)
        #expect(ShardRunner.silenceBound(forLongestTest: 100) == 300)
        #expect(ShardRunner.silenceBound(forLongestTest: 400) == 1200)
    }

    @Test
    func theShardPlanCarriesTheLongestTestEachShardIsGiven() throws {
        let tests = try (1 ... 3).map { try #require(TestIdentifier(enumerated: "DemoUnitTests/GizmoTests/t\($0)()")) }
        let seconds = [tests[0]: 400.0, tests[1]: 20.0, tests[2]: 10.0]

        let plan = ShardPlanner.plan(tests: tests, shards: 2) { seconds[$0] }

        #expect(plan.shards.map(\.longestTestSeconds) == [400, 20])
    }

    /// A shard whose plan predicts one 400 s test is not ended after 310 s of silence, and is ended past 1200 s.
    @Test(.timeLimit(.minutes(1)))
    func aShardPredictingA400SecondTestIsNotEndedAt310SecondsButIsPast1200() throws {
        let directory = try TemporaryDirectory.make("shard-silence")
        let clock = Clock()
        let stuck = DispatchSemaphore(value: 0)
        defer { stuck.signal() }
        let runner = ShardRunner(
            workingDirectory: directory,
            repositoryRoot: nil,
            children: SetAsideChildren(),
            launch: { assignment, _, _ in
                clock.advance(310)
                clock.awaitLooks(2)
                clock.advance(889)
                clock.awaitLooks(2)
                clock.advance(2)
                _ = stuck.wait(timeout: .now() + 5)
                return ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 0, wallSeconds: 1, logPath: "/tmp/shard-\(assignment.index).log")
            },
            now: { clock.now },
            patience: 0.1
        )
        let silence = ShardRunner.silenceBound(forLongestTest: 400)

        let outcomes = runner.run([ShardRunner.Assignment(index: 1, argv: ["/usr/bin/true"], bound: 100_000, silence: silence)])

        #expect(outcomes[0].ending == ShardOutcome.Ending(bound: .silence(1200), keptOwnResult: false))
        #expect(clock.endedAfter >= 1200)
    }

    /// The live launcher calls `heard` for the stderr chunk as well as the stdout one — both share one pipe — which is what keeps a real shard from being ended at the silence bound.
    @Test(.timeLimit(.minutes(1)))
    func theLiveLauncherReportsEveryChunkItReadsStderrIncluded() throws {
        let directory = try TemporaryDirectory.make("silence")
        let heard = Counter()

        _ = try RunLauncher(workingDirectory: directory).run(
            ["sh", "-c", "echo a; sleep 0.2; echo b 1>&2"],
            heard: { heard.bump() }
        )

        #expect(heard.count >= 2)
    }
}

private extension ShardSilenceBoundTests {
    final class Counter: @unchecked Sendable {
        private let gate = NSLock()
        private var value = 0

        var count: Int {
            gate.withLock { value }
        }

        func bump() {
            gate.withLock { value += 1 }
        }
    }

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

        var endedAfter: TimeInterval {
            gate.withLock { current.timeIntervalSinceReferenceDate }
        }

        func advance(_ seconds: TimeInterval) {
            gate.withLock { current += seconds }
        }

        func awaitLooks(_ count: Int) {
            gate.withLock {
                let target = reads + count
                let deadline = Date().addingTimeInterval(2)
                while reads < target, gate.wait(until: deadline) {}
            }
        }
    }
}
