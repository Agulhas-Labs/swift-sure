//
// Copyright © Agulhas Labs
//

import Foundation

/// What one suite, or one shard's suites together, are predicted to hold a `swift test` process for, in wall seconds.
struct PackageShardLoad {
    /// The suites charged, in the order they were added.
    var suites: [String]
    /// The wall clock predicted, before the process's own launch.
    var seconds: Double

    /// Takes `other`'s suites into this load.
    mutating func add(_ other: Self) {
        suites += other.suites
        seconds += other.seconds
    }
}
