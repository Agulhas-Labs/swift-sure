//
// Copyright © Agulhas Labs
//

import Foundation

/// What a run decided about its boots and what each shard's boot came to, behind one lock because the boot threads write it side by side.
public final class SlimBootRecord: @unchecked Sendable {
    private let gate = NSLock()
    private var decided: BootMode?
    private var outcomes: [Int: ShardBoot] = [:]
    private var labels: [Int: [String]] = [:]
    private var firstReadFailure: String?

    public init() {}

    /// The run's decision, or `nil` before it is made.
    public var mode: BootMode? {
        gate.withLock { decided }
    }

    /// Each shard's outcome by shard index; a shard booted stock has none.
    public var shards: [Int: ShardBoot] {
        gate.withLock { outcomes }
    }

    /// The first build settings read's failure, where a second read worked; `nil` where the first read was the one used.
    public var retriedRead: String? {
        gate.withLock { firstReadFailure }
    }

    func noteRetriedRead(firstFailure: String) {
        gate.withLock { firstReadFailure = firstFailure }
    }

    func decide(_ mode: BootMode) {
        gate.withLock { decided = mode }
    }

    func wrote(_ written: [String], forShard index: Int) {
        gate.withLock { labels[index] = written }
    }

    func written(forShard index: Int) -> [String]? {
        gate.withLock { labels[index] }
    }

    func record(_ outcome: ShardBoot, forShard index: Int) {
        gate.withLock { outcomes[index] = outcome }
    }

    /// Drops what was recorded for every shard at `count` or beyond, whose devices a lowered plan deleted before they ran.
    func forget(shardsFrom count: Int) {
        gate.withLock {
            outcomes = outcomes.filter { $0.key < count }
            labels = labels.filter { $0.key < count }
        }
    }
}
