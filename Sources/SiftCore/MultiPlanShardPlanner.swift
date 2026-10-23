//
// Copyright © Agulhas Labs
//

import Foundation

/// Plans a run over several test plans onto one pool of devices, where the unit of work is a (plan, test) item and the unit of overhead is a (shard, plan) call.
///
/// **A plan's tests stay together unless splitting them pays.** Each plan starts as one piece; a piece is placed on the shard where it adds least, and it adds an overhead only where that shard does not already run its plan. The plan whose split shortens the makespan most is then split one piece further, and so on until no split shortens it — so a plan spans several devices only where that buys back more than the extra call costs.
///
/// **A test in two plans is two items**, planned, run and reconciled once in each.
public struct MultiPlanShardPlanner: Sendable {
    /// Partitions every plan's tests into at most `requested` shards, keeping the highest count whose makespan is better by at least one overhead, as ``ShardPlanner`` does.
    public static func plan(
        _ plans: [PlanTests],
        shards requested: Int,
        overheadSeconds: Double = ShardPlanner.overheadSeconds,
        duration: (TestIdentifier) -> Double?
    ) -> MultiPlanShardPlan {
        let allTests = plans.flatMap(\.tests)
        let known = allTests.compactMap(duration)
        let estimate = median(of: known) ?? ShardPlanner.unknownTestSeconds
        let knownByTarget = Dictionary(grouping: allTests.filter { duration($0) != nil }, by: \.target)
            .compactMapValues { median(of: $0.compactMap(duration)) }
        let charged = plans.map { plan in
            Charged(plan: plan.plan, tests: plan.tests.map { (test: $0, seconds: duration($0) ?? knownByTarget[$0.target] ?? estimate) }.sorted(by: longestFirst))
        }
        let considered = max(1, min(requested, allTests.count, ShardPlanner.maximumShards))
        var best = partition(charged, into: 1, overheadSeconds: overheadSeconds)
        var bestMakespan = makespan(of: best)
        let measuredThroughout = known.count == allTests.count
        for count in stride(from: 2, through: considered, by: 1) {
            let shards = partition(charged, into: count, overheadSeconds: overheadSeconds)
            let span = makespan(of: shards)
            if !measuredThroughout || span - (bestMakespan - overheadSeconds) <= tolerance {
                best = shards
                bestMakespan = span
            }
        }
        return MultiPlanShardPlan(
            plans: plans.map(\.plan),
            shards: best,
            requestedShards: requested,
            overheadSeconds: overheadSeconds,
            estimatedTests: allTests.count - known.count,
            estimatedByPlan: Dictionary(plans.map { ($0.plan, $0.tests.count { duration($0) == nil }) }, uniquingKeysWith: +),
            estimatedSeconds: estimate
        )
    }
}

private extension MultiPlanShardPlanner {
    static var tolerance: Double {
        1e-9
    }

    /// One plan's tests with what each is charged, longest first.
    struct Charged {
        let plan: String
        let tests: [(test: TestIdentifier, seconds: Double)]
    }

    /// One plan's share of its tests, before it is placed on a shard.
    struct Piece {
        let plan: Int
        let tests: [(test: TestIdentifier, seconds: Double)]

        var seconds: Double {
            tests.reduce(0) { $0 + $1.seconds }
        }
    }

    static func longestFirst(_ left: (test: TestIdentifier, seconds: Double), _ right: (test: TestIdentifier, seconds: Double)) -> Bool {
        left.seconds == right.seconds ? left.test.enumerated < right.test.enumerated : left.seconds > right.seconds
    }

    /// The best partition into `count` shards this search finds: every plan whole, then the most rewarding split, one at a time.
    static func partition(_ plans: [Charged], into count: Int, overheadSeconds: Double) -> [MultiPlanShardPlan.Shard] {
        var pieces = plans.map { _ in 1 }
        var best = place(plans, pieces: pieces, into: count, overheadSeconds: overheadSeconds)
        while true {
            var improved: (pieces: [Int], shards: [MultiPlanShardPlan.Shard])?
            for index in plans.indices where pieces[index] < min(count, plans[index].tests.count) {
                var trial = pieces
                trial[index] += 1
                let shards = place(plans, pieces: trial, into: count, overheadSeconds: overheadSeconds)
                if isShorter(shards, than: improved?.shards ?? best) {
                    improved = (trial, shards)
                }
            }
            guard let improved else {
                return best
            }
            pieces = improved.pieces
            best = improved.shards
        }
    }

    /// Whether `shards` finish sooner than `other`, or finish together with fewer shards at the end: two plans tied for longest each need a split, and neither one alone shortens the run.
    static func isShorter(_ shards: [MultiPlanShardPlan.Shard], than other: [MultiPlanShardPlan.Shard]) -> Bool {
        let span = makespan(of: shards)
        let otherSpan = makespan(of: other)
        if abs(span - otherSpan) > tolerance {
            return span < otherSpan
        }
        return shards.count { abs($0.predictedSeconds - span) <= tolerance } < other.count { abs($0.predictedSeconds - otherSpan) <= tolerance }
    }

    /// Splits each plan into its number of pieces, then places the pieces longest first where each adds least: a piece's own seconds, and an overhead where the shard does not already run its plan.
    static func place(_ plans: [Charged], pieces: [Int], into count: Int, overheadSeconds: Double) -> [MultiPlanShardPlan.Shard] {
        var all: [Piece] = []
        for index in plans.indices {
            for tests in split(plans[index].tests, into: pieces[index]) where !tests.isEmpty {
                all.append(Piece(plan: index, tests: tests))
            }
        }
        all.sort { left, right in
            left.seconds == right.seconds ? left.plan < right.plan : left.seconds > right.seconds
        }
        var loads = Array(repeating: 0.0, count: count)
        var held = Array(repeating: [Int: [(test: TestIdentifier, seconds: Double)]](), count: count)
        for piece in all {
            func added(_ shard: Int) -> Double {
                piece.seconds + (held[shard][piece.plan] == nil ? overheadSeconds : 0)
            }
            var target = 0
            for shard in loads.indices where loads[shard] + added(shard) < loads[target] + added(target) - tolerance {
                target = shard
            }
            loads[target] += added(target)
            held[target][piece.plan, default: []] += piece.tests
        }
        // A shard no piece reached is no device at all: the pieces were fewer than the count tried.
        let used = (0 ..< count).filter { !held[$0].isEmpty }
        return used.enumerated().map { position, shard in
            let segments = held[shard].keys.sorted().map { plan in
                let tests = held[shard][plan, default: []].sorted(by: longestFirst)
                return MultiPlanShardPlan.Segment(
                    plan: plans[plan].plan,
                    tests: tests.map(\.test),
                    predictedSeconds: overheadSeconds + tests.reduce(0) { $0 + $1.seconds },
                    longestTestSeconds: tests.map(\.seconds).max() ?? 0
                )
            }
            return MultiPlanShardPlan.Shard(index: position + 1, segments: segments)
        }
    }

    /// A plan's tests, longest first, dealt into `count` pieces by always filling the lightest.
    static func split(_ tests: [(test: TestIdentifier, seconds: Double)], into count: Int) -> [[(test: TestIdentifier, seconds: Double)]] {
        var bins = Array(repeating: [(test: TestIdentifier, seconds: Double)](), count: count)
        var loads = Array(repeating: 0.0, count: count)
        for entry in tests {
            var target = 0
            for index in loads.indices where loads[index] < loads[target] - tolerance {
                target = index
            }
            bins[target].append(entry)
            loads[target] += entry.seconds
        }
        return bins
    }

    /// When the slowest shard is predicted to finish; an empty shard counts as nothing.
    static func makespan(of shards: [MultiPlanShardPlan.Shard]) -> Double {
        shards.map(\.predictedSeconds).max() ?? 0
    }

    static func median(of seconds: [Double]) -> Double? {
        let sorted = seconds.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

public extension MultiPlanShardPlanner {
    /// One plan's enumerated tests, as the planner is handed them.
    struct PlanTests: Sendable, Equatable {
        public let plan: String
        public let tests: [TestIdentifier]

        public init(plan: String, tests: [TestIdentifier]) {
            self.plan = plan
            self.tests = tests
        }
    }
}
