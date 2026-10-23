//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Covers the devices line's account of how the shards booted, from a decision and the shards' outcomes alone.
struct ShardBootLineTests {
    private static var slimText: String {
        "slim: 1 of 4 services off (iOS 27.0, profile v1), kept for the project: healthKit 2"
    }

    // MARK: - One mode for every shard

    /// Every shard slim reads as the decision's own text.
    @Test
    func everyShardSlimReadsAsTheDecision() {
        let clause = ShardBootLine.clause(mode: Self.slim, shards: [0: .slim, 1: .slim, 2: .slim])

        #expect(clause == Self.slimText)
    }

    /// A project declaring nothing keeps nothing, and says so.
    @Test
    func aProjectDeclaringNothingKeepsNothing() {
        let clause = ShardBootLine.clause(mode: Self.slim(healthKit: false), shards: [0: .slim])

        #expect(clause == "slim: 3 of 4 services off (iOS 27.0, profile v1), kept for the project: nothing")
    }

    /// Each reason a run boots stock reads as `stock:` and the reason.
    @Test
    func stockRunsSayWhy() {
        #expect(ShardBootLine.clause(mode: .stock(.requested), shards: [:]) == "stock: --stock")
        #expect(ShardBootLine.clause(mode: .stock(.noProfile(osVersion: "26.4")), shards: [:]) == "stock: no service profile for iOS 26.4")
        #expect(ShardBootLine.clause(mode: .stock(.unreadable("Gizmo/Gizmo.entitlements: no such file")), shards: [:])
            == "stock: the project's declarations could not be read (Gizmo/Gizmo.entitlements: no such file)")
        #expect(ShardBootLine.clause(mode: .stock(.unmapped(["NSLocationWhenInUseUsageDescription", "UIBackgroundModes:audio"])), shards: [:])
            == "stock: the project declares what no rule maps (NSLocationWhenInUseUsageDescription, UIBackgroundModes:audio)")
    }

    /// A retried build settings read adds one clause after the verdict, slim or stock.
    @Test
    func aRetriedReadAddsOneClauseAfterTheVerdict() {
        let note = " (the first build settings read failed: xcodebuild: error: transient; the second worked)"

        #expect(ShardBootLine.clause(mode: Self.slim, shards: [0: .slim], retriedRead: "xcodebuild: error: transient") == Self.slimText + note)
        #expect(ShardBootLine.clause(mode: .stock(.requested), shards: [:], retriedRead: "xcodebuild: error: transient") == "stock: --stock" + note)
        #expect(ShardBootLine.clause(mode: nil, shards: [:], retriedRead: "xcodebuild: error: transient") == nil)
    }

    /// A run that decided nothing adds no clause.
    @Test
    func anUndecidedRunAddsNoClause() {
        #expect(ShardBootLine.clause(mode: nil, shards: [:]) == nil)
    }

    // MARK: - Shards that differ

    /// Shards are grouped by number, 1-based and ascending, in the order slim, not slim, unverified.
    @Test
    func shardsThatDifferAreGroupedByNumber() {
        let shards: [Int: ShardBoot] = [
            3: .unverified("the read-back timed out"),
            2: .notSlim("the runtime did not apply the override (0 of 1 read back)"),
            1: .slim,
            0: .slim,
        ]

        let clause = ShardBootLine.clause(mode: Self.slim, shards: shards)

        #expect(clause == "slim on shards 1, 2 (1 of 4 services off, iOS 27.0, profile v1, kept for the project: healthKit 2); "
            + "not slim on shard 3: the runtime did not apply the override (0 of 1 read back); "
            + "slim, unverified on shard 4: the read-back timed out")
    }

    /// Shards not slim for different reasons are separate groups; for one reason, one group.
    @Test
    func shardsAreGroupedByReasonToo() {
        let shards: [Int: ShardBoot] = [0: .notSlim("first"), 1: .notSlim("second"), 2: .notSlim("first")]

        let clause = ShardBootLine.clause(mode: Self.slim(healthKit: false), shards: shards)

        #expect(clause == "not slim on shards 1, 3: first; not slim on shard 2: second")
    }

    // MARK: - Order on the line

    /// The boot clause follows the counts and an already-gone device, and comes before a tmp directory left and a device left behind.
    @Test
    func theClauseSitsBetweenTheCountsAndWhatWasLeft() {
        let cleanup = ShardDevices.Cleanup(created: 3, deletions: [
            ShardDevices.Deletion(udid: "AAAA", wasAlreadyGone: true),
            ShardDevices.Deletion(udid: "BBBB", tmpDirectoryLeft: "/private/var/tmp/BBBB (Operation not permitted)"),
            ShardDevices.Deletion(udid: "CCCC", failure: "busy"),
        ])

        let line = cleanup.summary(bootClause: Self.slimText)

        #expect(line?.hasPrefix("3 simulators created, 2 deleted (1 was already gone) · \(Self.slimText); tmp directory left: /private/var/tmp/BBBB (Operation not permitted) — 1 left: CCCC — run: ") == true)
    }

    /// With no clause the line is what it was.
    @Test
    func noClauseLeavesTheLineAlone() {
        let cleanup = ShardDevices.Cleanup(created: 1, deletions: [ShardDevices.Deletion(udid: "AAAA")])

        #expect(cleanup.summary(bootClause: nil) == "1 simulator created, 1 deleted")
        #expect(cleanup.summary == "1 simulator created, 1 deleted")
    }

    // MARK: - Whether the re-run names --stock

    /// A slim or unverified shard may be what failed the tests; a stock run, or one whose every shard fell back, has nothing to rule out.
    @Test
    func onlyASlimBootIsWorthRulingOut() {
        #expect(ShardBootLine.bootedSlim(mode: Self.slim, shards: [0: .slim]))
        #expect(ShardBootLine.bootedSlim(mode: Self.slim, shards: [0: .notSlim("x"), 1: .unverified("y")]))
        #expect(!ShardBootLine.bootedSlim(mode: Self.slim, shards: [0: .notSlim("x")]))
        #expect(!ShardBootLine.bootedSlim(mode: .stock(.requested), shards: [:]))
        #expect(!ShardBootLine.bootedSlim(mode: nil, shards: [:]))
    }

    // MARK: - Fixtures

    private static var slim: BootMode {
        slim(healthKit: true)
    }

    private static func slim(healthKit: Bool) -> BootMode {
        BootMode.decide(
            stockRequested: false, runtimeIdentifier: runtime, osVersion: "27.0",
            profileLookup: { _ in profile },
            declarations: { .success(ProjectDeclarations(entitlements: healthKit ? ["com.apple.developer.healthkit"] : [])) }
        )
    }

    private static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    }

    /// Four services: three the profile disables and one the runtime needs, two of the disabled serving HealthKit.
    private static let profile: ServiceProfile = {
        func entry(_ label: String, _ disposition: Disposition) -> ServiceEntry {
            ServiceEntry(label: label, domain: .daemon, start: .onDemand, ranAtBoot: true, peakFootprintMB: nil, cpuSeconds: nil, disposition: disposition)
        }
        return ServiceProfile(
            profileVersion: 1,
            runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A000"),
            deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            generated: "2026-10-01",
            method: ProfileMethod(costWindowSeconds: 60, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
            services: [entry("com.gizmo.a", .disable), entry("com.gizmo.b", .disable), entry("com.gizmo.c", .disable), entry("com.gizmo.core", .core)],
            capabilities: [.healthKit: ["com.gizmo.a", "com.gizmo.b"]]
        )
    }()
}
