//
// Copyright © Agulhas Labs
//

import Foundation

/// A wrapped `swift test` the run stopped because it did not exit after its test process ended, and the crash report that process left where one qualifies.
///
/// The verdict is failed, and the exit code is the stopped command's own: `128 + 15` for the SIGTERM, 137 where it took the SIGKILL.
public struct RunStoppedTest: Sendable, Equatable {
    /// How long the output had been quiet when the command was stopped.
    public let quiet: TimeInterval
    /// The crash report this run's test process left, or `nil` where none qualifies.
    public let crash: RunCrashReport?

    public init(quiet: TimeInterval, crash: RunCrashReport?) {
        self.quiet = quiet
        self.crash = crash
    }

    /// The lines that open the run's answer: the verdict, then the crash report where there is one.
    public var lines: [String] {
        let seconds = quiet.rounded() == quiet ? String(Int(quiet)) : String(quiet)
        return ["✘ swift test did not exit \(seconds) s after its test process ended; stopped it"] + (crash.map { [$0.line] } ?? [])
    }
}
