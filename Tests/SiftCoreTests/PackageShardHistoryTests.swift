//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A SwiftPM package planned from what its shards' walls cost per test, never from the clocks its tests read while they waited beside each other.
@Suite(.temporaryDirectories)
struct PackageShardHistoryTests {
    private static func tests(_ counts: [String: Int]) throws -> [TestIdentifier] {
        let lines = counts.sorted { $0.key < $1.key }.flatMap { suite, count in (0 ..< count).map { "LibTests.\(suite)/t\($0)()" } }
        return try PackageShardPlanner.listed(lines.joined(separator: "\n"))
    }

    private static func shard(tests: Int, wall: Double, missing: Int = 0, retried: Bool = false, exitCode: Int32 = 0, timedOut: Bool = false) -> ShardReconciliation.Shard {
        var shard = ShardReconciliation.Shard(
            index: 1, testCount: tests, iterations: 1, wallSeconds: wall, executionSeconds: wall, predictedSeconds: wall, exitCode: exitCode, logPath: "",
            recording: TestDurationStore.Recording(observations: [], retried: retried, missing: missing), closedWithRunSummary: true
        )
        shard.timedOut = timedOut
        return shard
    }

    private static func recorded(_ wall: Double, tests: Int = 100, shards: Int, package: String = ".", into store: inout TestDurationStore, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let recording = try #require(
            TestDurationStore.Recording(packageShards: [shard(tests: tests, wall: wall)], requestedShards: shards, package: package),
            sourceLocation: sourceLocation
        )
        store.record(recording)
    }

    @Test func aParallelRunsTestDurationsDoNotSkewThePartition() throws {
        let root = try TemporaryDirectory.make("history-skew")
        var store = TestDurationStore(repositoryRoot: root)
        let listed = try Self.tests(["AlphaTests": 10, "BetaTests": 10, "LampTests": 10, "PalletTests": 10])
        // What a parallel run recorded: every test of one suite read 25,000 s, and the suite's span read as long.
        let skewed = listed.filter { PackageShardPlanner.suite(of: $0) == "LibTests.AlphaTests" }.map {
            TestDurationStore.Timing(identifier: $0.enumerated, seconds: 25000, iteration: 1)
        } + [TestDurationStore.Timing(identifier: "suite LibTests.AlphaTests", seconds: 750_000, iteration: 1)]
        store.record(TestDurationStore.Recording(observations: skewed))

        let plan = PackageShardPlanner.plan(tests: listed, shards: 2, history: store)

        #expect(plan.shards.map(\.tests.count) == [20, 20])
        #expect(plan.shards.allSatisfy { $0.predictedSeconds < 100 })
    }

    @Test func aRecordedShardWallPredictsByCount() throws {
        let root = try TemporaryDirectory.make("history-wall")
        var store = TestDurationStore(repositoryRoot: root)
        try Self.recorded(50, shards: 2, into: &store)
        let listed = try Self.tests(["AlphaTests": 30, "BetaTests": 30, "LampTests": 20, "PalletTests": 20])

        let plan = PackageShardPlanner.plan(tests: listed, shards: 2, history: store)

        #expect(plan.shards.map(\.tests.count) == [50, 50])
        for shard in plan.shards {
            #expect(abs(shard.predictedSeconds - PackageShardPlanner.overheadSeconds - Double(shard.tests.count) * 50 / 100) < 1e-9)
        }
    }

    @Test func aShardThatLostTestsOrRanTwiceIsNotRecorded() {
        #expect(TestDurationStore.Recording(packageShards: [Self.shard(tests: 10, wall: 5, missing: 1)], requestedShards: 1) == nil)
        #expect(TestDurationStore.Recording(packageShards: [Self.shard(tests: 10, wall: 5, retried: true)], requestedShards: 1) == nil)
    }

    @Test func aShardEndedByASignalOrItsBoundIsNotRecorded() {
        #expect(TestDurationStore.Recording(packageShards: [Self.shard(tests: 10, wall: 600, exitCode: 137)], requestedShards: 1) == nil)
        #expect(TestDurationStore.Recording(packageShards: [Self.shard(tests: 10, wall: 600, timedOut: true)], requestedShards: 1) == nil)
        #expect(TestDurationStore.Recording(packageShards: [Self.shard(tests: 10, wall: 5, exitCode: 1)], requestedShards: 1) != nil)
    }

    @Test func aRunAtOneShardCountDoesNotPredictAnother() throws {
        let root = try TemporaryDirectory.make("history-count")
        var store = TestDurationStore(repositoryRoot: root)
        try Self.recorded(50, shards: 1, into: &store)
        let listed = try Self.tests(["AlphaTests": 5, "BetaTests": 5, "LampTests": 5, "PalletTests": 5])

        let plan = PackageShardPlanner.plan(tests: listed, shards: 4, history: store)

        #expect(store.packageSecondsPerTest(shards: 4, package: ".") == nil)
        #expect(plan.shards.map(\.tests.count) == [5, 5, 5, 5])
        #expect(plan.shards.allSatisfy { $0.predictedSeconds == plan.shards[0].predictedSeconds })
        let empty = try TestDurationStore(repositoryRoot: TemporaryDirectory.make("history-count-empty"))
        let first = PackageShardPlanner.plan(tests: listed, shards: 4, history: empty)
        #expect(plan.shards.map(\.predictedSeconds) == first.shards.map(\.predictedSeconds))
    }

    @Test func twoPackagesInOneRepositoryDoNotShareACost() throws {
        let root = try TemporaryDirectory.make("history-packages")
        var store = TestDurationStore(repositoryRoot: root)
        try Self.recorded(50, shards: 2, package: ".", into: &store)
        try Self.recorded(500, shards: 2, package: "Tools/Gizmo", into: &store)

        #expect(store.packageSecondsPerTest(shards: 2, package: ".") == 0.5)
        #expect(store.packageSecondsPerTest(shards: 2, package: "Tools/Gizmo") == 5)
        #expect(store.packageSecondsPerTest(shards: 2, package: "Tools/Other") == nil)
    }

    @Test func aPackageIsKeyedByItsPathFromTheRepositoryRoot() {
        let root = URL(fileURLWithPath: "/tmp/gizmo-repo")

        #expect(PackageTestRun.costKeyPath(of: root, in: root) == ".")
        #expect(PackageTestRun.costKeyPath(of: root.appendingPathComponent("Tools/Gizmo"), in: root) == "Tools/Gizmo")
        #expect(PackageTestRun.costKeyPath(of: URL(fileURLWithPath: "/tmp/gizmo-repo-other"), in: root) == ".")
    }

    @Test func aFirstRunWithNothingRecordedIsEvenBySuiteCount() throws {
        let root = try TemporaryDirectory.make("history-empty")
        let store = TestDurationStore(repositoryRoot: root)
        let listed = try Self.tests(["AlphaTests": 5, "BetaTests": 5, "LampTests": 5, "PalletTests": 5])

        let plan = PackageShardPlanner.plan(tests: listed, shards: 2, history: store)

        #expect(plan.shards.map(\.tests.count) == [10, 10])
    }
}
