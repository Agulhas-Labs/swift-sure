//
// Copyright © Agulhas Labs
//

import Foundation

/// The devices of a run over several plans, each working through its own segments: one thread per device, each segment one call through the shard runner, one after the other.
///
/// **A device holds one call at a time.** A shard of a ``MultiPlanShardPlan`` runs one `xcodebuild` per plan it was given, and two on one simulator at once would fight over it, so a lane hands the runner one assignment, waits it out, and only then hands it the next.
///
/// **A lane's device can go once its last call has ended**, while the others still run, as a single-plan shard's does: every lane but the last to finish is named to `ended`, after the runner has ended its session, and none is named once the run is stopped — a cancelled run's devices are the teardown's.
struct PlanLanes: Sendable {
    let shards: TestRunEnvironment.Shards

    /// Whether the run has been cancelled, after which no segment is started and no lane is named.
    let stopped: @Sendable () -> Bool

    /// Runs every lane at once and returns when the last is done: each lane's outcomes in its segments' order, the lanes in the order given.
    ///
    /// A segment the cancellation reached before it started reports what a shard that never ran does — nothing, under `SIGTERM`'s code — so every segment still owes the merge an outcome.
    func run(_ lanes: [Lane], ended: @escaping @Sendable (Lane) -> Void) -> [[ShardOutcome]] {
        let results = Results(count: lanes.count)
        let remaining = Remaining(count: lanes.count)
        let finished = DispatchSemaphore(value: 0)
        for (slot, lane) in lanes.enumerated() {
            Thread.detachNewThread {
                var outcomes: [ShardOutcome] = []
                for segment in lane.segments {
                    guard !stopped() else {
                        outcomes.append(Self.unrun)
                        continue
                    }
                    outcomes.append(shards.run([segment]).first ?? Self.unrun)
                }
                results.put(outcomes, at: slot)
                if !remaining.finishOne(), !stopped() {
                    ended(lane)
                }
                finished.signal()
            }
        }
        for _ in lanes {
            finished.wait()
        }
        return results.taken()
    }
}

extension PlanLanes {
    /// One device's work: the shard it runs, the device, and one assignment per segment in the order they run.
    struct Lane: Sendable {
        let index: Int
        let udid: String
        let segments: [ShardRunner.Assignment]
    }
}

private extension PlanLanes {
    /// What a segment that never ran reports, as ``ShardRunner`` reports a shard that never ran.
    static var unrun: ShardOutcome {
        ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGTERM, wallSeconds: 0, logPath: "", failures: [])
    }

    /// Each lane's outcomes, written from the lane's own thread.
    final class Results: @unchecked Sendable {
        private let gate = NSLock()
        private var outcomes: [[ShardOutcome]]

        init(count: Int) {
            outcomes = Array(repeating: [], count: count)
        }

        func put(_ lane: [ShardOutcome], at slot: Int) {
            gate.withLock { outcomes[slot] = lane }
        }

        func taken() -> [[ShardOutcome]] {
            gate.withLock { outcomes }
        }
    }

    /// The lanes still working, so the last to finish knows it is the last.
    final class Remaining: @unchecked Sendable {
        private let gate = NSLock()
        private var count: Int

        init(count: Int) {
            self.count = count
        }

        /// Counts one lane finished, answering whether it was the last.
        func finishOne() -> Bool {
            gate.withLock {
                count -= 1
                return count < 1
            }
        }
    }
}
