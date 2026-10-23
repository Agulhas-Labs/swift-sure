//
// Copyright © Agulhas Labs
//

import Foundation
import os

/// A test seam, inert unless a test installs a handler: told the arguments and the directory of every git ``GitContext`` starts, from whichever thread starts it.
///
/// Process-wide rather than task-local, since the stop hook judges off the calling thread; a test that installs one filters by directory and runs serialized.
struct GitSpawnObserver {
    typealias Handler = @Sendable (_ arguments: [String], _ directory: URL) -> Void

    /// The handler, held in a struct: a bare function read back through the lock's `inout` state came out wrapped in one more reabstraction thunk on every call, until about 6,000 spawns into a run one call overflowed its thread's stack.
    private struct Installed {
        let handler: Handler
    }

    private static let installed = OSAllocatedUnfairLock<Installed?>(initialState: nil)

    static func install(_ handler: @escaping Handler) {
        installed.withLock { $0 = Installed(handler: handler) }
    }

    static func remove() {
        installed.withLock { $0 = nil }
    }

    static func notify(_ arguments: [String], in directory: URL) {
        installed.withLock { $0 }?.handler(arguments, directory)
    }
}
