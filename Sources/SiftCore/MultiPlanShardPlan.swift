//
// Copyright © Agulhas Labs
//

import Foundation

/// The partition of a run that spans several test plans: each shard is one device, and runs one `xcodebuild` per plan it was given, one after the other.
///
/// **A segment is one call.** Each `xcodebuild test-without-building` runs from one plan's `.xctestrun`, so a shard holding two plans makes two calls on its device and pays the launch, session start and bundle load twice; a segment's predicted seconds carry that overhead, and a shard's are the sum of its segments.
public struct MultiPlanShardPlan: Sendable, Equatable {
    /// The plans this run covers, in the order the caller's selection gave them.
    public let plans: [String]

    /// The shards, numbered from 1, each with its plans' segments in the order they run.
    public let shards: [Shard]

    /// The shard count the caller asked for, before the planner clamped it to the work there is or lowered it.
    public let requestedShards: Int

    /// What every segment was charged before its first test — see ``ShardPlanner/overheadSeconds``.
    public let overheadSeconds: Double

    /// How many planned (plan, test) items had no recorded duration.
    public let estimatedTests: Int

    /// How many of each plan's items had no recorded duration, by plan name.
    public let estimatedByPlan: [String: Int]

    /// What an item with no recorded duration and no timed test in its target was charged.
    public let estimatedSeconds: Double
}

public extension MultiPlanShardPlan {
    /// One plan's tests on one shard: one `xcodebuild` call.
    struct Segment: Sendable, Equatable {
        public let plan: String
        public let tests: [TestIdentifier]

        /// The call's overhead plus the predicted seconds of every test in it.
        public let predictedSeconds: Double

        /// The longest any one test in this segment is predicted to take.
        public let longestTestSeconds: Double
    }

    /// One device's work: its segments, run in order.
    struct Shard: Sendable, Equatable {
        public let index: Int
        public let segments: [Segment]

        /// Every segment's predicted seconds, overheads included.
        public var predictedSeconds: Double {
            segments.reduce(0) { $0 + $1.predictedSeconds }
        }
    }

    /// The longest any one shard is predicted to take, which is what the run as a whole is predicted to take.
    var predictedMakespan: Double {
        shards.map(\.predictedSeconds).max() ?? 0
    }

    /// One plan's segments as a plan of its own, with each segment under the index of the shard that runs it, which is what that plan's reconciliation is read against.
    func projected(plan name: String, displayNames: [String: [TestIdentifier]] = [:], conditional: Set<TestIdentifier> = []) -> ShardPlan {
        let shards = shards.compactMap { shard -> ShardPlan.Shard? in
            guard let segment = shard.segments.first(where: { $0.plan == name }) else {
                return nil
            }
            return ShardPlan.Shard(index: shard.index, tests: segment.tests, predictedSeconds: segment.predictedSeconds, longestTestSeconds: segment.longestTestSeconds)
        }
        return ShardPlan(
            shards: shards,
            requestedShards: requestedShards,
            overheadSeconds: overheadSeconds,
            estimatedTests: estimatedByPlan[name] ?? 0,
            estimatedSeconds: estimatedSeconds,
            displayNames: displayNames,
            conditional: conditional,
            lowering: nil
        )
    }
}
