//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation

/// Watches one running `swift test` for ``RunTestStall`` and stops it by its own pid: SIGTERM, then SIGKILL after the rule's grace where it is still there.
///
/// **Never the group.** Whatever still holds the output pipe is named first, from the command's process group or session, and is never signalled: only the `swift test` pid is stopped.
///
/// **Only the command it first looked at.** Its start time is taken at the first look, and no signal goes unless the pid still holds a process with that start time that has not exited: a command that exited by itself and waits to be reaped, or a process that reused its pid, is never signalled.
///
/// Driven by the one thread reading the command's output, which hands it the time on every wake; nothing here waits.
final class RunTestStallWatch {
    let pid: Int32
    let rule: RunTestStall
    private let children: (Int32) -> [RunTestStall.Child]
    private let command: (Int32) -> RunTestStall.Command?
    private let send: (Int32, Int32) -> Void
    /// Every test process this run saw among the command's children, a zombie's included.
    private(set) var testProcesses: Set<Int32> = []
    /// What was running in the command's group or session, less the command and its zombies, when it was stopped.
    private(set) var holders: RunHeldOutput?
    /// When the SIGTERM went, or `nil` while the command has not been stopped.
    private(set) var stoppedAt: Date?
    /// Whether the SIGKILL went after the SIGTERM.
    private(set) var killed = false
    /// The command's start time at the first look, or `nil` where nothing held its pid then.
    private var commandStart: UInt64?
    /// When the command was first seen with no live child, or `nil` while it has one.
    private var childlessSince: Date?
    private var lastLook: Date?

    init(
        pid: Int32,
        rule: RunTestStall,
        children: @escaping (Int32) -> [RunTestStall.Child] = RunTestStall.children(of:),
        command: @escaping (Int32) -> RunTestStall.Command? = RunTestStall.command(of:),
        send: @escaping (Int32, Int32) -> Void = { _ = kill($0, $1) }
    ) {
        self.pid = pid
        self.rule = rule
        self.children = children
        self.command = command
        self.send = send
    }

    /// The longest the reader may wait for output before handing the time over again, in whole milliseconds.
    var wait: Int32 {
        Int32(min(max(1, (rule.look * 1000).rounded(.up)), Double(Int32.max)))
    }

    /// Looks at the command at `now`, at most once a look interval: records the test processes among its children, stops it where the rule says so, and sends SIGKILL once the grace after the SIGTERM has passed.
    func look(lastHeard: Date, now: Date) {
        if let lastLook, now.timeIntervalSince(lastLook) < rule.look {
            return
        }
        if lastLook == nil {
            commandStart = command(pid)?.start
        }
        lastLook = now
        if let stoppedAt {
            if !killed, now.timeIntervalSince(stoppedAt) >= rule.killAfter, isStillTheCommand() {
                killed = true
                send(pid, SIGKILL)
            }
            return
        }
        let current = children(pid)
        testProcesses.formUnion(current.filter { RunTestStall.isTestProcess(named: $0.name) }.map(\.pid))
        if current.allSatisfy(\.isZombie) {
            childlessSince = childlessSince ?? now
        } else {
            childlessSince = nil
        }
        guard rule.stalls(quietSince: lastHeard, childlessSince: childlessSince, now: now, sawTestProcess: !testProcesses.isEmpty), isStillTheCommand() else {
            return
        }
        let zombies = Set(current.filter(\.isZombie).map(\.pid))
        holders = RunHeldOutput(holders: RunHeldOutput.left(by: pid).holders.filter { $0.pid != pid && !zombies.contains($0.pid) })
        stoppedAt = now
        send(pid, SIGTERM)
    }

    /// Whether the command's exit code is that of the signal this watch sent it: 143 after the SIGTERM, 137 after the SIGKILL.
    ///
    /// Any other code, a 0 above all, is the command's own exit and no stop.
    func stopped(exitCode: Int32) -> Bool {
        stoppedAt != nil && (exitCode == 128 + SIGTERM || (killed && exitCode == 128 + SIGKILL))
    }

    /// Whether `pid` still holds the process first looked at, and it has not exited.
    private func isStillTheCommand() -> Bool {
        guard let commandStart, let current = command(pid) else {
            return false
        }
        return !current.isZombie && current.start == commandStart
    }
}
