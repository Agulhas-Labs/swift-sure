//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers when a running `swift test` is stopped and where the signal goes, with the children, the command's own record and the time handed in: no process is started and nothing waits.
struct RunTestStallWatchTests {
    private static let rule = RunTestStall(quiet: 30, look: 1, killAfter: 2, crashReports: RunCrashReports(directory: URL(fileURLWithPath: "/nonexistent"), shownAs: "~"))
    private static let pid: Int32 = 2_000_001
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let helper = RunTestStall.Child(pid: 2_000_002, name: "swiftpm-testing-", isZombie: false)
    private static let deadHelper = RunTestStall.Child(pid: 2_000_002, name: "swiftpm-testing-", isZombie: true)
    private static let running = RunTestStall.Command(start: 1_700_000_000_000_000, isZombie: false)

    /// A command quiet past the window whose test process is a zombie is sent SIGTERM at its own pid, never at its group.
    @Test
    func theStopGoesToTheCommandsOwnPidNotItsGroup() {
        let run = Self.watch(looking: [[Self.helper], [Self.deadHelper]])

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(31))

        #expect(run.sent.signals == [Signal(target: Self.pid, signal: SIGTERM)])
        #expect(run.watch.stoppedAt == Self.start.addingTimeInterval(31))
        #expect(run.watch.testProcesses == [Self.helper.pid])
    }

    /// A command with no child left at all after its test process was seen is stopped too.
    @Test
    func aCommandWithNoChildAfterItsTestProcessIsStopped() {
        let run = Self.watch(looking: [[Self.helper], []])

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(31))

        #expect(run.sent.signals == [Signal(target: Self.pid, signal: SIGTERM)])
    }

    /// A command that exited by itself and waits to be reaped, one whose pid a process started since has taken, or one already reaped is never signalled, however quiet and childless it was.
    @Test(arguments: [
        RunTestStall.Command(start: running.start, isZombie: true),
        RunTestStall.Command(start: running.start + 1, isZombie: false),
        nil,
    ])
    func aCommandThatIsNoLongerTheOneFirstSeenIsNotSignalled(_ later: RunTestStall.Command?) {
        let run = Self.watch(looking: [[Self.helper], []])

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.command.current = later
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(31))

        #expect(run.sent.signals.isEmpty)
        #expect(run.watch.stoppedAt == nil)
    }

    /// The command still there once the grace after the SIGTERM has passed takes the SIGKILL, at its own pid.
    @Test
    func theCommandStillThereAfterTheGraceTakesTheKill() {
        let run = Self.watch(looking: [[Self.helper], []])

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(31))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(33))

        #expect(run.sent.signals == [Signal(target: Self.pid, signal: SIGTERM), Signal(target: Self.pid, signal: SIGKILL)])
    }

    /// A process that took the command's pid after the SIGTERM ended it never takes the SIGKILL.
    @Test
    func aProcessThatReusedThePidAfterTheStopTakesNoKill() {
        let run = Self.watch(looking: [[Self.helper], []])

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(31))
        run.command.current = RunTestStall.Command(start: Self.running.start + 1, isZombie: false)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(33))

        #expect(run.sent.signals == [Signal(target: Self.pid, signal: SIGTERM)])
    }

    /// A stop is the exit by the signal sent: 143 after the SIGTERM, 137 only once the SIGKILL went, and never 0.
    @Test
    func onlyTheExitCodeOfTheSignalSentIsAStop() {
        let run = Self.watch(looking: [[Self.helper], []])
        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(31))

        #expect(run.watch.stopped(exitCode: 128 + SIGTERM))
        #expect(!run.watch.stopped(exitCode: 0))
        #expect(!run.watch.stopped(exitCode: 1))
        #expect(!run.watch.stopped(exitCode: 128 + SIGKILL))

        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(33))

        #expect(run.watch.stopped(exitCode: 128 + SIGKILL))
    }

    /// The window counts the childless state as well as the quiet: the instant between one quiet child ending and the next starting, as between a coverage merge and its report, stops nothing, and a childless state that lasts the whole window does.
    @Test
    func aRunBetweenTwoChildrenIsNotStoppedInTheGap() {
        let merge = RunTestStall.Child(pid: 2_000_003, name: "llvm-profdata", isZombie: false)
        let report = RunTestStall.Child(pid: 2_000_005, name: "llvm-cov", isZombie: false)
        let run = Self.watch(looking: [[Self.helper], [Self.deadHelper, merge], [Self.deadHelper], [Self.deadHelper, report], [Self.deadHelper]])

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(40))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(41))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(75))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(104))

        #expect(run.sent.signals.isEmpty)

        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(105))

        #expect(run.sent.signals == [Signal(target: Self.pid, signal: SIGTERM)])
    }

    /// A command with a live child — a quiet coverage merge here — is never stopped, however long it has been quiet.
    @Test
    func aRunWithALiveChildIsNotStopped() {
        let merge = RunTestStall.Child(pid: 2_000_003, name: "llvm-profdata", isZombie: false)
        let run = Self.watch(looking: [[Self.helper], [Self.deadHelper, merge]])

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(600))

        #expect(run.sent.signals.isEmpty)
        #expect(run.watch.stoppedAt == nil)
    }

    /// A command quiet for less than the window is not stopped, even with no live child for longer.
    @Test
    func aRunQuietUnderTheWindowIsNotStopped() {
        let run = Self.watch(looking: [[Self.helper], [Self.deadHelper]])
        let heard = Self.start.addingTimeInterval(2)

        run.watch.look(lastHeard: Self.start, now: Self.start)
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(1))
        run.watch.look(lastHeard: heard, now: heard.addingTimeInterval(29.9))

        #expect(run.sent.signals.isEmpty)
        #expect(run.watch.stoppedAt == nil)
    }

    /// A build phase that has launched no test process yet is never stopped, however quiet and childless it is.
    @Test
    func aRunThatNeverStartedATestProcessIsNotStopped() {
        let compiler = RunTestStall.Child(pid: 2_000_004, name: "swift-frontend", isZombie: true)
        let run = Self.watch(looking: [[compiler], []])

        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(31))
        run.watch.look(lastHeard: Self.start, now: Self.start.addingTimeInterval(62))

        #expect(run.sent.signals.isEmpty)
    }

    /// The names the kernel gives SwiftPM's two test processes are recognised, and a compiler's is not.
    @Test
    func theTestProcessNamesAreTheHelperAndTheXCTestHost() {
        #expect(RunTestStall.isTestProcess(named: "swiftpm-testing-"))
        #expect(RunTestStall.isTestProcess(named: "swiftpm-testing-helper"))
        #expect(RunTestStall.isTestProcess(named: "xctest"))
        #expect(!RunTestStall.isTestProcess(named: "swift-frontend"))
        #expect(!RunTestStall.isTestProcess(named: "swift"))
        #expect(!RunTestStall.isTestProcess(named: nil))
    }

    /// A watch on a pid no process holds, whose looks see `looking` in turn, whose command is what `command` holds (a running one until a test changes it), and whose signals are recorded rather than sent.
    private static func watch(looking: [[RunTestStall.Child]]) -> Run {
        let sent = Sent()
        let looks = Looks(looking)
        let held = Held(running)
        let watch = RunTestStallWatch(
            pid: pid,
            rule: rule,
            children: { _ in looks.next() },
            command: { _ in held.current },
            send: { sent.signals.append(Signal(target: $0, signal: $1)) }
        )
        return Run(watch: watch, sent: sent, command: held)
    }
}

extension RunTestStallWatchTests {
    /// One signal the watch sent.
    struct Signal: Equatable {
        let target: Int32
        let signal: Int32
    }

    /// The signals sent, in order.
    private final class Sent {
        var signals: [Signal] = []
    }

    /// A watch under test, with the signals it sent and the command record it sees.
    private struct Run {
        let watch: RunTestStallWatch
        let sent: Sent
        let command: Held
    }

    /// The command record every lookup sees until a test changes it.
    private final class Held {
        var current: RunTestStall.Command?

        init(_ current: RunTestStall.Command?) {
            self.current = current
        }
    }

    /// The children each look sees, the last repeated once the list runs out.
    private final class Looks {
        private var remaining: [[RunTestStall.Child]]

        init(_ looks: [[RunTestStall.Child]]) {
            remaining = looks
        }

        func next() -> [RunTestStall.Child] {
            remaining.count > 1 ? remaining.removeFirst() : remaining.first ?? []
        }
    }
}
