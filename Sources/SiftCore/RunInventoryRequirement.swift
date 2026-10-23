//
// Copyright © Agulhas Labs
//

import Foundation

/// What `--require-inventory` asks of a run: the exit code an unclean inventory turns into, and the line a run owes where the inventory printed none.
public struct RunInventoryRequirement {
    /// What `swift-sure run --require-inventory` exits with when the wrapped command exited 0 and the inventory it was held to is not clean: a code neither `swift test` nor `xcodebuild` exits with.
    public static let exitCode: Int32 = 6

    /// The line a run owes under the flag where ``RunInventoryCheck`` printed none, and whether that absence is itself unclean.
    ///
    /// A `swift test` the inventory bounds but that reported no test has nothing to reconcile and is unclean; a run the inventory does not apply to (filtered, `--parallel`, `xcodebuild`, not a test command) says why it was not checked and is clean, so it keeps its exit code.
    public static func absence(of arguments: [String], report: RunReport?) -> (line: String, unclean: Bool) {
        let prefix = "inventory: not checked — "
        guard RunCommandKind.executesTests(arguments) else {
            return (prefix + "the command does not run tests", false)
        }
        if RunInventoryCheck.narrowsAnyRun(arguments) {
            return (prefix + "the run was filtered, so it does not run the whole inventory", false)
        }
        guard RunCommandKind.recognize(arguments) == .swiftTest else {
            return (prefix + "an xcodebuild test run is bounded by its scheme, not by a package manifest", false)
        }
        if report?.parallelSwiftTest == true {
            return (prefix + "a --parallel run's log names only some of the tests it ran, so there is no list to reconcile", false)
        }
        return (prefix + "no test ran to reconcile", true)
    }
}
