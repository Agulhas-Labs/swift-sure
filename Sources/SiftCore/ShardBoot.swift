//
// Copyright © Agulhas Labs
//

import Foundation

/// How one shard's device came up, as the read-back after its boot found it.
public enum ShardBoot: Sendable, Equatable {
    /// Every label the override wrote is listed as disabled on the booted device.
    case slim

    /// The device ran without the override, with the reason.
    case notSlim(String)

    /// The override was written and the read-back could not say whether it applied, with the reason.
    case unverified(String)
}
