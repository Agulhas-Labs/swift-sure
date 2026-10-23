//
// Copyright © Agulhas Labs
//

import Foundation

/// Runs a plan's shards side by side and hands back what each one left, in shard order.
///
/// The order is the whole point of this type existing rather than the caller writing a loop: a shard is identified by the position its outcome stands in — the merge reads `outcomes[offset]` against `plan.shards[offset]` — while the order shards *finish* in is whatever the host's load makes it. A runner that handed back completions in the order they arrived would attribute the fast shard's tests to the slow shard's plan, and every count downstream of that is wrong while looking right.
///
/// A shard that fails, times out or cannot be started at all takes none of the others down with it: each one is supervised on its own, and what the merge gets back is one outcome per assignment whatever happened to any of them.
public struct ShardRunner: Sendable {
    private let children: SetAsideChildren
    private let launch: Launch
    private let now: @Sendable () -> Date
    private let patience: TimeInterval
    private let state = State()

    /// A runner for a repository's shards, with the live launcher unless a caller injects its own.
    ///
    /// `launch` is a seam rather than a convenience: everything this type owns — the ordering, the bound, the cancellation — has to be provable without starting an `xcodebuild`, and a test that starts one proves nothing in a second. `patience` is how long a shard that was just ended is given to hand back what its log held before the runner answers for it.
    public init(
        workingDirectory: URL,
        repositoryRoot: URL?,
        children: SetAsideChildren,
        run: String? = nil,
        launch: Launch? = nil,
        now: @escaping @Sendable () -> Date = ShardRunner.sleeplessNow,
        patience: TimeInterval = 5
    ) {
        self.children = children
        self.now = now
        self.patience = patience
        self.launch = launch ?? Self.live(
            workingDirectory: workingDirectory,
            repositoryRoot: repositoryRoot,
            children: children,
            run: run,
            now: now
        )
    }
}

public extension ShardRunner {
    /// One shard's work: which shard it is, the exact argv to run, and the wall clock it is allowed.
    ///
    /// The argv arrives complete — ``TestInvocation`` builds it — because a runner that assembled arguments would be a second place the invocation is decided, and the two would drift.
    struct Assignment: Sendable {
        public let index: Int
        public let argv: [String]
        public let bound: TimeInterval

        /// How long the shard may print nothing before it is ended: ``ShardRunner/silenceBound(forLongestTest:)`` of its longest predicted test.
        public let silence: TimeInterval

        public init(index: Int, argv: [String], bound: TimeInterval, silence: TimeInterval = ShardRunner.silenceBound) {
            self.index = index
            self.argv = argv
            self.bound = bound
            self.silence = silence
        }
    }

    /// How one shard is started: it runs `argv`, hands its process id to the first callback, calls the second on every chunk of output it reads, and answers with what the run left.
    ///
    /// The pid is the first callback's whole reason for being there — a shard past a bound is ended by session, and the session's id is the pid of the process the launcher started. The second is how the supervisor knows the shard is still working: a shard that has printed nothing for ``silenceBound`` is ended.
    typealias Launch = @Sendable (Assignment, @Sendable @escaping (Int32) -> Void, @Sendable @escaping () -> Void) throws -> ShardOutcome

    /// The wall clock a shard predicted to take `seconds` is allowed in all before it is ended: a ceiling, not the bound that ends a stuck shard.
    ///
    /// A wall clock cannot tell slow from stuck — under load a healthy shard's wall varies twofold, and one serialized fixture-heavy suite prints nothing for minutes while still working — so a stuck shard is ended by ``silenceBound``, and this only ends one that keeps printing for far longer than any run of it has taken. Three times the prediction, because a prediction is a median of past runs and three shards under load are slower than any of them alone; an hour's floor, because the prediction of a short shard is small enough that host contention alone would blow a proportional bound, and a bound that fires on a healthy run costs a whole suite. The second parameter is that floor — `swift-sure test --shard-timeout` replaces it for a caller who has already measured that this suite never needs it, and `TestCommand` refuses anything below the sane minimum before this is ever reached.
    static func bound(forPredicted seconds: Double, minimumSeconds: TimeInterval = 60 * 60) -> TimeInterval {
        max(3 * seconds, minimumSeconds)
    }

    /// How long a shard may print nothing before it is ended as stuck.
    ///
    /// Five minutes, because the longest single test measured alone takes under four seconds and the longest quiet seen in a working shard — a serialized suite whose fixtures each build a package — was under three minutes: a shard quiet this long is waiting on something that will not come.
    static var silenceBound: TimeInterval {
        5 * 60
    }

    /// How long a shard whose longest predicted test takes `seconds` may print nothing: three times that test, never under ``silenceBound``.
    ///
    /// A simulator shard prints a test's line when the test finishes, so one healthy test longer than the floor is silent that long. A test with no prediction counts at the median it is charged (its target's, else the plan's), so an untimed test is allowed for as a typical one, not as none.
    static func silenceBound(forLongestTest seconds: Double) -> TimeInterval {
        max(silenceBound, 3 * seconds)
    }

    /// The clock a live supervisor reads: the system's uptime, which stops while the machine sleeps, so a laptop closed over a shard's quiet does not end every shard on waking.
    @Sendable
    static func sleeplessNow() -> Date {
        Date(timeIntervalSinceReferenceDate: ProcessInfo.processInfo.systemUptime)
    }

    /// Runs every assignment at once and returns when the last one is done, one outcome per assignment in shard order.
    ///
    /// A thread of its own per shard, not a queue: every thread here spends its whole life blocked — the shard's on a child process that runs for minutes, its supervisor's on the semaphore that says the child is done — and work like that on a shared concurrent queue waits behind whatever else the process is doing before it so much as starts. A bound measured from a start that was itself delayed is not a bound.
    ///
    /// `ended` is told the index of every shard but the last to finish, once its supervisor has ended that shard's session itself — the moment nothing can drive its device any more, so the caller can delete the device while the others are still running rather than after all of them. It is called on the shard's supervisor thread before `run` can return, so it has to hand anything slow to a thread of its own: a delete waited out here would be added to the slowest shard's time. The last shard is not named, because its device is the caller's teardown's to delete, which follows at once.
    ///
    /// **No shard is named once the run is cancelled.** ``cancel()`` takes every session still running and ends them one at a time, seconds each, so a supervisor that returns meanwhile can have found its session already taken and ended nothing: its `xcodebuild` can still be alive, and a device deleted under one wedges CoreSimulator. Every device of a cancelled run is the teardown's, which ends the sessions first.
    func run(_ assignments: [Assignment], ended: @escaping @Sendable (Int) -> Void = { _ in }) -> [ShardOutcome] {
        let ordered = assignments.sorted { $0.index < $1.index }
        let results = Results(count: ordered.count, unrun: Self.unrun(after: 0))
        let supervised = DispatchSemaphore(value: 0)
        let unfinished = Unfinished(count: ordered.count)
        for (slot, assignment) in ordered.enumerated() {
            Thread.detachNewThread {
                self.supervise(assignment, slot: slot, into: results)
                if !unfinished.finishOne(), !self.state.isCancelled {
                    ended(assignment.index)
                }
                supervised.signal()
            }
        }
        for _ in ordered {
            supervised.wait()
        }
        return results.taken()
    }

    /// Ends every shard still running and stops any that has not started, so that `run` answers with what the logs hold rather than being waited on.
    ///
    /// Called from a signal handler, where the alternative is a run killed outright leaving three `xcodebuild`s and three booted simulators behind it.
    func cancel() {
        let running = state.cancelling()
        // Asked to stop all at once and cleaned up one at a time: the ask is what makes them all start
        // ending in the same moment, and the cleanup below then finds most of them already gone.
        for session in running {
            Self.stop(session)
        }
        for session in running {
            children.settle(session.pid)
        }
    }
}

private extension ShardRunner {
    /// How often a supervisor looks up from waiting to check the bounds and the cancellation.
    ///
    /// Short enough that a cancelled run answers while somebody is still watching it, and long enough that an hour's ceiling costs tens of thousands of wakeups rather than a spinning core.
    static var pollSeconds: TimeInterval {
        0.05
    }

    /// What a shard that never ran reports: nothing, under the code a shell gives a process a `SIGTERM` ended.
    ///
    /// Empty rather than absent, because every assignment owes the merge an outcome — the tests it was given are then missing by the ordinary rule, which is exactly what they are.
    static func unrun(after seconds: Double) -> ShardOutcome {
        ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 128 + SIGTERM, wallSeconds: seconds, logPath: "", failures: [])
    }

    /// Waits out one shard, ending it at its ceiling, after ``Assignment/silence`` with no output, or on a cancellation, and files what it left.
    func supervise(_ assignment: Assignment, slot: Int, into results: Results) {
        guard !state.isCancelled else {
            var unstarted = Self.unrun(after: 0)
            unstarted.endedByInterruption = true
            results.seal(unstarted, at: slot)
            return
        }
        let finished = DispatchSemaphore(value: 0)
        let started = now()
        let heard = Heard(at: started)
        Thread.detachNewThread {
            defer { finished.signal() }
            do {
                let outcome = try self.launch(assignment, { pid in
                    // A pid recorded after the run was cancelled is a child nothing else will ever end:
                    // the sweep over the running shards has already been made.
                    if !self.state.record(pid, forShard: assignment.index) {
                        self.children.settle(pid)
                    }
                }, { heard.record(self.now()) })
                results.put(outcome, at: slot)
            } catch {
                results.put(Self.failed(toStart: error), at: slot)
            }
        }
        while finished.wait(timeout: .now() + Self.pollSeconds) == .timedOut {
            if state.isCancelled {
                collect(assignment, slot: slot, from: finished, into: results, ended: nil, since: started)
                return
            }
            let current = now()
            if current.timeIntervalSince(started) >= assignment.bound {
                collect(assignment, slot: slot, from: finished, into: results, ended: .ceiling(assignment.bound), since: started)
                return
            }
            if current.timeIntervalSince(heard.last) >= assignment.silence {
                collect(assignment, slot: slot, from: finished, into: results, ended: .silence(assignment.silence), since: started)
                return
            }
        }
        settle(shard: assignment.index)
        // A shard that came back on its own just as the run was cancelled is still a cancelled run's shard: the flag is set before any session is stopped, so the marking does not depend on this supervisor's poll having seen it first.
        if state.isCancelled {
            results.seal(ending: nil, interrupted: true, at: slot)
        }
    }

    /// Ends a shard's session and takes whatever it hands back within `patience`, answering for it when it hands back nothing; `bound` is the one that fired, `nil` for a cancellation.
    ///
    /// The wait is what makes a bound worth having rather than merely honest: an ended `xcodebuild` closes its pipe within milliseconds, and the log it wrote up to that point holds every test that did finish — throwing that away would turn a bound into a shard's worth of missing tests every time it fired.
    func collect(
        _ assignment: Assignment,
        slot: Int,
        from finished: DispatchSemaphore,
        into results: Results,
        ended bound: ShardOutcome.Ending.Bound?,
        since started: Date
    ) {
        // Asked to stop, waited for, and only then cleaned up after — in that order, because the shard's
        // leader stays in the process table as a zombie until the thread waiting on it reaps it, and a
        // cleanup that runs first would wait out its own SIGKILL grace on a process that is already dead.
        if let session = state.session(forShard: assignment.index) {
            Self.stop(session)
        }
        let answered = finished.wait(timeout: .now() + patience) == .success
        settle(shard: assignment.index)
        if answered {
            results.seal(ending: bound.map { ShardOutcome.Ending(bound: $0, keptOwnResult: true) }, interrupted: bound == nil, at: slot)
            return
        }
        // Nothing came back, so the runner is the only thing that can say how long the shard had: the
        // note the merge writes names that number, and a zero there would read as a shard that never ran.
        var outcome = Self.unrun(after: now().timeIntervalSince(started))
        outcome.ending = bound.map { ShardOutcome.Ending(bound: $0, keptOwnResult: false) }
        outcome.endedByInterruption = bound == nil
        results.seal(outcome, at: slot)
    }

    /// Ends whatever is left of a shard's session, once and once only.
    func settle(shard index: Int) {
        guard let session = state.take(shard: index) else {
            return
        }
        children.settle(session.pid)
    }

    /// Asks everything in a shard's session to stop, without waiting for any of it.
    ///
    /// `SIGTERM` and no more: what has to happen at a bound is that the shard stops producing, and what has to happen *promptly* is that the thread reading its output sees the end of it. Whatever ignores this is ended outright by the settle that follows.
    static func stop(_ session: SetAsideChildren.Session) {
        for member in SetAsideChildren.members(of: session) {
            kill(member, SIGTERM)
        }
    }

    /// What a shard whose executable never started reports: the error's own sentence, under the code a shell gives a command it could not run.
    static func failed(toStart error: Error) -> ShardOutcome {
        var outcome = ShardOutcome(
            outcomes: RunTestOutcomes(),
            exitCode: 127,
            wallSeconds: 0,
            logPath: "",
            failures: []
        )
        outcome.launchFailure = "\(error)"
        return outcome
    }

    /// The live launcher: one `.swift-sure/runs/` log and one parsed report per shard, through the same path a wrapped `swift-sure run` takes.
    ///
    /// The report is taken whatever its verdict says, because a shard's verdict is not the run's: the reconciliation decides what ran, and a filter that could not explain a failure still read every ending the log carried.
    static func live(
        workingDirectory: URL,
        repositoryRoot: URL?,
        children: SetAsideChildren,
        run: String?,
        now: @escaping @Sendable () -> Date
    ) -> Launch {
        { assignment, launched, heard in
            let launcher = RunLauncher(workingDirectory: workingDirectory, repositoryRoot: repositoryRoot, runToken: run)
            let started = now()
            let outcome = try launcher.run(assignment.argv, children: children, heard: heard, launched: launched)
            return shard(from: outcome, wallSeconds: now().timeIntervalSince(started))
        }
    }
}

extension ShardRunner {
    /// What a shard's own run comes to as the merge reads it: its outcomes, code, log and failures, whether it closed every Swift Testing run, and the stop the stall watch made of it.
    static func shard(from outcome: RunOutcome, wallSeconds: Double) -> ShardOutcome {
        var shard = ShardOutcome(
            outcomes: outcome.report?.testOutcomes ?? RunTestOutcomes(),
            exitCode: outcome.exitCode,
            wallSeconds: wallSeconds,
            logPath: outcome.log?.url.path ?? "",
            failures: outcome.report?.testFailures ?? []
        )
        shard.closedWithRunSummary = outcome.report.map(closedEverySwiftTestingRun) ?? false
        shard.stoppedTest = outcome.stoppedTest
        shard.terminatingSignal = outcome.terminatingSignal
        return shard
    }

    /// Whether `report` carries a `Test run with …` line for every Swift Testing process it opened, and at least one, since each bundle's process prints its own and a second one that crashed leaves the first one's line standing.
    static func closedEverySwiftTestingRun(_ report: RunReport) -> Bool {
        let closings = report.summaryLines.count { RunOutputFilter.undecorated($0).hasPrefix("Test run with ") }
        return closings > 0 && closings >= report.swiftTestingProcessOpenings
    }
}

private extension ShardRunner {
    /// What the shards share: whether the run has been cancelled, and the session each shard still running was started in.
    ///
    /// The session rather than the pid alone, because a pid on its own is not an identity: a child reaped a moment before a signal is sent is a pid the kernel may have handed to somebody else, and ``SetAsideChildren/members(of:)`` refuses one whose start time has changed.
    final class State: @unchecked Sendable {
        private let gate = NSLock()
        private var cancelled = false
        private var running: [Int: SetAsideChildren.Session] = [:]

        var isCancelled: Bool {
            gate.withLock { cancelled }
        }

        /// Records a shard's session, answering `false` when the run was already cancelled — the one case where the caller has to end the child itself.
        func record(_ pid: Int32, forShard index: Int) -> Bool {
            let session = SetAsideChildren.Session(pid: pid, started: KernelProcess.startMicroseconds(of: pid) ?? 0)
            return gate.withLock {
                guard !cancelled else {
                    return false
                }
                running[index] = session
                return true
            }
        }

        /// A shard's session while it is still recorded, for a signal that does not end the runner's interest in it.
        func session(forShard index: Int) -> SetAsideChildren.Session? {
            gate.withLock { running[index] }
        }

        /// Takes a shard's session, so that the supervisor and a cancellation racing for it end it once between them.
        func take(shard index: Int) -> SetAsideChildren.Session? {
            gate.withLock { running.removeValue(forKey: index) }
        }

        /// Cancels the run and takes every session still recorded, for the same reason.
        func cancelling() -> [SetAsideChildren.Session] {
            gate.withLock {
                cancelled = true
                let sessions = Array(running.values)
                running.removeAll()
                return sessions
            }
        }
    }

    /// When a shard last printed anything, written by the thread reading its output and read by its supervisor.
    final class Heard: @unchecked Sendable {
        private let gate = NSLock()
        private var lastHeard: Date

        init(at started: Date) {
            lastHeard = started
        }

        var last: Date {
            gate.withLock { lastHeard }
        }

        func record(_ moment: Date) {
            gate.withLock { lastHeard = moment }
        }
    }

    /// How many shards are still being supervised, so that the one that finishes last is known as it finishes.
    final class Unfinished: @unchecked Sendable {
        private let gate = NSLock()
        private var remaining: Int

        init(count: Int) {
            remaining = count
        }

        /// Counts one shard finished, answering whether it was the last.
        func finishOne() -> Bool {
            gate.withLock {
                remaining -= 1
                return remaining == 0
            }
        }
    }

    /// One slot per shard, filled by whichever of the shard and its supervisor answers for it first.
    ///
    /// Sealing is what keeps a bound honest: a shard ended at its bound has already been answered for, and a worker that comes back afterwards must not overwrite that answer with one that says nothing went wrong.
    final class Results: @unchecked Sendable {
        private let gate = NSLock()
        private var outcomes: [ShardOutcome]
        private var sealed: Set<Int> = []

        init(count: Int, unrun: ShardOutcome) {
            outcomes = Array(repeating: unrun, count: count)
        }

        func put(_ outcome: ShardOutcome, at slot: Int) {
            gate.withLock {
                guard !sealed.contains(slot) else {
                    return
                }
                outcomes[slot] = outcome
            }
        }

        /// Seals what the shard itself filed, marking it as ended where it was, at a bound or by the run's interruption.
        func seal(ending: ShardOutcome.Ending?, interrupted: Bool, at slot: Int) {
            gate.withLock {
                outcomes[slot].ending = ending
                outcomes[slot].endedByInterruption = interrupted
                sealed.insert(slot)
            }
        }

        /// Seals an outcome the supervisor had to answer with, because the shard handed back nothing in time.
        func seal(_ outcome: ShardOutcome, at slot: Int) {
            gate.withLock {
                outcomes[slot] = outcome
                sealed.insert(slot)
            }
        }

        func taken() -> [ShardOutcome] {
            gate.withLock { outcomes }
        }
    }
}
