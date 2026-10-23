//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// Stopping stub children from many tasks at once never leaves a cooperative-pool thread blocked on a child's exit.
struct DeadlineChildReapStressTests {
    /// More concurrent stoppers than there are cooperative threads each launch, kill and reap a child; all of them finish, well inside the limit.
    ///
    /// Launching and reaping over a hundred processes is work that slows with the host's load; a hang is still caught, as no stop waits unbounded.
    ///
    /// This is a liveness smoke test: it cannot fail on the base, only catch a stop that hangs.
    @Test(.timeLimit(.minutes(3))) func manyConcurrentKillsAreAllReaped() async throws {
        let children = DeadlineChildTests.Children()
        defer { children.stopAll() }
        let count = max(64, ProcessInfo.processInfo.activeProcessorCount * 2)

        let stopped = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< count {
                group.addTask {
                    let child = try children.launch("trap '' TERM; exec sleep 100000")
                    await children.stop(child)
                    return !child.isRunning
                }
            }
            return try await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }

        #expect(stopped == count)
    }
}
