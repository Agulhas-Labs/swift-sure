//
// Copyright © Agulhas Labs
//

import Foundation

/// A cross-process exclusive lock on a file, for the read-modify-write cycles several processes run against one small state file.
///
/// **A save being atomic does not make the load, the mutation and the save atomic.** Two processes that each load a file, change it and write it back can both load before either saves, and whichever saves last erases the other's change without an error anywhere. Holding this lock across the whole cycle serialises them.
///
/// `flock` rather than an exclusive-create lock file, because the kernel releases it when the descriptor closes — including when the process dies holding it — so there is no stale lock to time out and no wedged process. It blocks rather than spinning: the critical sections it guards are one small read and one small write. Each call opens its own descriptor, so two calls contend even inside one process.
///
/// **Unavailable is not fatal.** A directory that cannot be created or a lock that cannot be taken runs the body anyway, unserialised — the callers are hooks and best-effort registries that may never fail closed.
public struct ExclusiveFileLock {
    /// Runs `body` with an exclusive lock on the file at `lockURL` held, creating the file (and its directory) when missing.
    public static func withLock<T>(at lockURL: URL, _ body: () -> T) -> T {
        guard (try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil
        else {
            return body()
        }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return body() }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            // A signal interrupting the wait is not a failure to lock; anything else is, and runs unlocked.
            guard errno == EINTR else { return body() }
        }
        defer { flock(descriptor, LOCK_UN) }
        return body()
    }
}
