//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation

/// When a wrapped `swift test` that has not exited is stopped: a test process seen, no child of it still running, and its output quiet for ``quiet`` counted from the later of its last output and the moment it was first seen with no live child.
///
/// A test process that dies can leave `swift test` waiting for the end of an output pipe that something else still holds, and nothing else ever ends that wait. A legitimately quiet test keeps a live child, so this never stops one; a build phase that has launched no test process yet is never stopped, and a quiet coverage merge keeps its own child alive. A zombie child counts as gone: it runs nothing and holds nothing. The window counts the childless state as well as the quiet, so the instant between one quiet child ending and the next starting, as between `llvm-profdata merge` and `llvm-cov export`, never stops a run.
///
/// Injected rather than fixed, as every wall-clock window here is: a test drives it with small values, and the crash reports it names are read from a directory the caller chooses.
public struct RunTestStall: Sendable {
    /// How long the output must have been quiet, and the command without a live child, before it is stopped.
    public let quiet: TimeInterval
    /// How often the command's children are looked at while it runs.
    public let look: TimeInterval
    /// How long after the SIGTERM a command still there is sent SIGKILL.
    public let killAfter: TimeInterval
    /// Where the crash report a stopped run names is looked for.
    public let crashReports: RunCrashReports

    public init(quiet: TimeInterval, look: TimeInterval, killAfter: TimeInterval, crashReports: RunCrashReports) {
        self.quiet = quiet
        self.look = look
        self.killAfter = killAfter
        self.crashReports = crashReports
    }

    /// The rule of every real invocation: thirty quiet seconds, a look each second, SIGKILL two seconds after the SIGTERM.
    public static let standard = RunTestStall(quiet: 30, look: 1, killAfter: 2, crashReports: .live)

    /// Whether the command is to be stopped at `now`: a test process seen, and for the whole window both quiet since `lastHeard` and without a live child since `childlessSince`, which is `nil` while it has one.
    func stalls(quietSince lastHeard: Date, childlessSince: Date?, now: Date, sawTestProcess: Bool) -> Bool {
        guard sawTestProcess, let childlessSince else {
            return false
        }
        return now.timeIntervalSince(max(lastHeard, childlessSince)) >= quiet
    }

    /// Whether `name`, as the kernel gives it, is a test process SwiftPM starts: Swift Testing's helper, whose name the kernel cuts to sixteen bytes, or XCTest's host.
    static func isTestProcess(named name: String?) -> Bool {
        guard let name, !name.isEmpty else {
            return false
        }
        return name == "xctest" || (name.count >= 15 && "swiftpm-testing-helper".hasPrefix(name))
    }
}

public extension RunTestStall {
    /// One child of the command, as the kernel recorded it when it was looked at.
    struct Child: Sendable, Equatable {
        public let pid: Int32
        public let name: String?
        /// Whether it has exited and not been reaped.
        public let isZombie: Bool

        public init(pid: Int32, name: String?, isZombie: Bool) {
            self.pid = pid
            self.name = name
            self.isZombie = isZombie
        }
    }

    /// The watched command itself, as the kernel recorded it when it was looked at.
    struct Command: Sendable, Equatable {
        /// When it was started, in microseconds since 1970: what a process that reuses its pid cannot share.
        public let start: UInt64
        /// Whether it has exited and not been reaped.
        public let isZombie: Bool

        public init(start: UInt64, isZombie: Bool) {
            self.start = start
            self.isZombie = isZombie
        }
    }
}

extension RunTestStall {
    /// Every process whose parent is `pid` right now, zombies included.
    static func children(of pid: Int32) -> [Child] {
        KernelProcess.allPids().compactMap { candidate in
            guard let record = KernelProcess.record(of: candidate), record.kp_eproc.e_ppid == pid else {
                return nil
            }
            return Child(pid: candidate, name: KernelProcess.name(of: candidate), isZombie: record.kp_proc.p_stat == SZOMB)
        }
    }

    /// The process holding `pid` right now, or `nil` where nothing holds it.
    static func command(of pid: Int32) -> Command? {
        guard let record = KernelProcess.record(of: pid), let start = KernelProcess.startMicroseconds(of: pid) else {
            return nil
        }
        return Command(start: start, isZombie: record.kp_proc.p_stat == SZOMB)
    }
}
