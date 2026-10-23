//
// Copyright © Agulhas Labs
//

import Foundation

/// How long each phase of a sharded run took, as the one line that says whether the build, the boots or the shards are the lever.
///
/// The phases are in the order the run passed through them, and add up to its wall clock from the build's start.
public struct ShardPhases: Equatable, Sendable {
    /// `build-for-testing`'s own wall clock.
    public let build: Double
    /// From the build's exit to the end of the enumeration: the `.xctestrun` lookup and the enumeration, while the devices boot.
    ///
    /// The plan follows the join and is arithmetic, so it is not in this phase.
    public let enumerate: Double
    /// From the end of the enumeration to the first shard's launch, which includes the plan made once the devices are joined: what the run waited on for its devices beyond the build and the enumeration they overlapped.
    public let devicesReady: Double
    /// From the first shard's launch to the last shard's exit.
    public let shards: Double
    /// From the last shard's exit until every device was deleted.
    public let teardown: Double

    public init(build: Double, enumerate: Double, devicesReady: Double, shards: Double, teardown: Double) {
        self.build = build
        self.enumerate = enumerate
        self.devicesReady = devicesReady
        self.shards = shards
        self.teardown = teardown
    }
}

public extension ShardPhases {
    /// The run's one timing line — `build 12s · enumerate 7s · devices ready +30s · shards 200s · teardown 6s`.
    var line: String {
        [
            "build \(ShardSeconds.text(build))",
            "enumerate \(ShardSeconds.text(enumerate))",
            "devices ready +\(ShardSeconds.text(devicesReady))",
            "shards \(ShardSeconds.text(shards))",
            "teardown \(ShardSeconds.text(teardown))",
        ].joined(separator: " · ")
    }
}
