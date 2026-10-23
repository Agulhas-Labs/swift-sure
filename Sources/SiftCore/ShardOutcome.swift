//
// Copyright © Agulhas Labs
//

import Foundation

/// What one shard's run left behind, as the merge reads it.
///
/// **The exit code is carried beside the outcomes and never folded into them.** A shard's process can exit non-zero over a log whose every test passed — a crashed runner, a failed teardown, a diagnostics timeout — and a merge that read only the test lines would answer green over it. Both facts reach ``ShardMerge`` and the verdict is taken over the pair.
public struct ShardOutcome: Sendable {
    /// Every test this shard's log reported starting or finishing.
    public let outcomes: RunTestOutcomes

    /// What the shard's `xcodebuild` exited with.
    public let exitCode: Int32

    /// How long the shard took from launch to exit, which is the number summed test time cannot see.
    public let wallSeconds: Double

    /// Where this shard's log was written, as the answer states it — moved by the caller where the log is kept past pruning.
    public var logPath: String

    /// The failures the filter read out of that log, for the answer's classification block.
    ///
    /// Bare outcomes carry an ending and a duration and nothing else, so a failure's message and location — which is all ``RunFailureShape`` groups by — have to come from the filter that read the same log.
    public let failures: [RunTestFailure]

    /// Which of the runner's bounds ended this shard instead of it finishing, or `nil` where none did.
    ///
    /// Set by the runner after the fact rather than passed in, because the shard itself cannot know: what it hands back is whatever its log held when the session was ended, which is indistinguishable from a short run that simply reported little. The merge owes the reader that sentence — the tests below the cut are missing by the ordinary rule, and a reader who is not told why reads them as crashes.
    public var ending: Ending?

    /// Whether this shard was ended at one of the runner's bounds instead of finishing.
    public var timedOut: Bool {
        ending != nil
    }

    /// The stop the run's stall watch made of this shard's `swift test` — quiet, with no live test process — or `nil` where it made none.
    ///
    /// Carried for the same reason as ``ending``: the stop ends the shard with the SIGTERM's code over a log that simply stops, and a reader who is not told who stopped it reads the tests after the cut as crashes.
    public var stoppedTest: RunStoppedTest?

    /// The sentence a shard whose executable never started carries, or `nil` where one started.
    ///
    /// A shard that could not be launched has no log to explain itself with, so the error's own words are the only thing the answer can print.
    public var launchFailure: String?

    /// The signal that ended this shard's command, or `nil` where it exited by itself or never ran.
    ///
    /// The exit code alone cannot carry it: a shell's `128 + N` is also a code a command can choose, and a signal SwiftSure did not send is the one ending nothing else on the outcome explains.
    public var terminatingSignal: Int32?

    /// Whether the run's interruption ended this shard, or kept it from starting.
    ///
    /// Set by the runner for the reason ``ending`` is: a shard SwiftSure cancelled ends with the `SIGTERM` SwiftSure sent it, which on its own reads as a signal from outside.
    public var endedByInterruption = false

    /// Whether SwiftSure accounts for how this shard ended: at a bound, by the stall watch's stop, by never starting it, or by the run's interruption.
    public var endedBySift: Bool {
        ending != nil || stoppedTest != nil || launchFailure != nil || endedByInterruption
    }

    /// Whether the log carries Swift Testing's closing `Test run with …` line for every Swift Testing process it opened, which a run that was cut short never prints — see ``ShardRunner/closedEverySwiftTestingRun(_:)``.
    public var closedWithRunSummary = false

    /// This shard's Swift Testing event stream, the record its Swift Testing tests are reconciled from, or `nil` where it has none — see ``ShardEventStream``.
    public var eventStream: ShardEventStream?

    /// Why a SwiftPM shard has no ``eventStream``, which the answer states where the console then shows Swift Testing ran; `nil` where it has one or was never asked for one.
    public var eventStreamAbsence: String?

    public init(
        outcomes: RunTestOutcomes,
        exitCode: Int32,
        wallSeconds: Double,
        logPath: String,
        failures: [RunTestFailure] = []
    ) {
        self.outcomes = outcomes
        self.exitCode = exitCode
        self.wallSeconds = wallSeconds
        self.logPath = logPath
        self.failures = failures
    }
}

public extension ShardOutcome {
    /// Which bound the runner ended a shard at, and whether the shard handed back what its log held once it was ended.
    struct Ending: Sendable, Equatable {
        public let bound: Bound
        /// Whether the outcome is the shard's own, read from its log after it was ended, rather than the runner's empty one for a shard that handed back nothing in time.
        public let keptOwnResult: Bool

        public init(bound: Bound, keptOwnResult: Bool) {
            self.bound = bound
            self.keptOwnResult = keptOwnResult
        }
    }
}

public extension ShardOutcome.Ending {
    /// Which of the two bounds a shard met first.
    enum Bound: Sendable, Equatable {
        /// The wall clock the shard was allowed in all, in seconds: a ceiling for the shard that is still working, since a working shard is ended by it only once it has run far past any prediction.
        case ceiling(TimeInterval)
        /// How long the shard had printed nothing when it was ended, in seconds: the bound that ends a stuck shard.
        case silence(TimeInterval)
    }
}
