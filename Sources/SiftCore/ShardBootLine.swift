//
// Copyright © Agulhas Labs
//

import Foundation

/// The clause of the devices line that says how the shards booted, and whether a slim boot is in play for a re-run to rule out.
struct ShardBootLine {
    /// The clause without its leading separator, or `nil` where the run decided nothing.
    ///
    /// Shards are keyed by the 0-based order their devices were created in and print 1-based, as the shard lines do.
    static func clause(mode: BootMode?, shards: [Int: ShardBoot], retriedRead: String? = nil) -> String? {
        let clause = verdict(mode: mode, shards: shards)
        guard let clause, let retriedRead else {
            return clause
        }
        return "\(clause) (the first build settings read failed: \(retriedRead); the second worked)"
    }

    private static func verdict(mode: BootMode?, shards: [Int: ShardBoot]) -> String? {
        guard let mode else {
            return nil
        }
        guard case let .slim(boot) = mode else {
            return mode.text
        }
        let slim = shards.filter { $0.value == .slim }.keys.sorted()
        let notSlim = grouped(shards, reason: notSlimReason)
        let unverified = grouped(shards, reason: unverifiedReason)
        guard !notSlim.isEmpty || !unverified.isEmpty else {
            return mode.text
        }
        var groups: [String] = []
        if !slim.isEmpty {
            groups.append("slim on \(shardList(slim)) (\(boot.servicesOff), iOS \(boot.profile.runtime.version), profile v\(boot.profile.profileVersion), \(boot.keptText))")
        }
        groups.append(contentsOf: notSlim.map { "not slim on \(shardList($0.shards)): \($0.reason)" })
        groups.append(contentsOf: unverified.map { "slim, unverified on \(shardList($0.shards)): \($0.reason)" })
        return groups.joined(separator: "; ")
    }

    /// Whether the re-run is worth telling to add `--stock`: the mode is slim and a shard booted slim or could not be shown not to have.
    static func bootedSlim(mode: BootMode?, shards: [Int: ShardBoot]) -> Bool {
        guard case .slim = mode else {
            return false
        }
        return shards.values.contains { boot in
            switch boot {
            case .slim, .unverified: true
            case .notSlim: false
            }
        }
    }

    private static func notSlimReason(_ boot: ShardBoot) -> String? {
        if case let .notSlim(reason) = boot {
            return reason
        }
        return nil
    }

    private static func unverifiedReason(_ boot: ShardBoot) -> String? {
        if case let .unverified(reason) = boot {
            return reason
        }
        return nil
    }

    /// The shards whose outcome carries a reason, grouped by that reason in the order of each reason's first shard.
    private static func grouped(_ shards: [Int: ShardBoot], reason: (ShardBoot) -> String?) -> [Group] {
        var groups: [Group] = []
        for index in shards.keys.sorted() {
            guard let found = shards[index].flatMap(reason) else {
                continue
            }
            if let match = groups.firstIndex(where: { $0.reason == found }) {
                groups[match].shards.append(index)
            } else {
                groups.append(Group(reason: found, shards: [index]))
            }
        }
        return groups
    }

    private static func shardList(_ indices: [Int]) -> String {
        "shard\(indices.count == 1 ? "" : "s") " + indices.map { String($0 + 1) }.joined(separator: ", ")
    }
}

extension ShardBootLine {
    private struct Group {
        let reason: String
        var shards: [Int]
    }
}
