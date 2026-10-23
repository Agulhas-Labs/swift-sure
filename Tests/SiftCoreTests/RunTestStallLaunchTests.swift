//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers a wrapped `swift test` that never exits after its test process ended, run for real: a stand-in `swift` starts a short-lived `xctest`, leaves a `sleep` in its process group holding the output, and becomes a `sleep` that never reaps its child.
///
/// The windows are injected and small; every process here ends within twenty seconds on its own, and the holder is ended by pid when the test finishes.
@Suite(.temporaryDirectories)
struct RunTestStallLaunchTests {
    private static let patience = RunOutputPatience(grace: 0.2, cap: 5)

    /// The command is stopped by its own pid: the holder in its process group is named and still running afterwards, and the exit code is the SIGTERM's.
    @Test(.timeLimit(.minutes(2)))
    func aStoppedSwiftTestIsSignalledByItsPidAndItsHolderIsNamedNotEnded() throws {
        let root = try TemporaryDirectory.make("run-stall-launch-term")
        defer { try? FileManager.default.removeItem(at: root) }
        let holderFile = root.appendingPathComponent("holder")
        defer { Self.endHolder(recordedIn: holderFile) }
        let swift = try Self.standIn(in: root, before: "( /bin/sleep 20 & echo $! > '\(holderFile.path)' )")
        var launched: Int32 = 0

        let outcome = try Self.run(swift, in: root, killAfter: 120) { launched = $0 }

        let holder = try #require(Self.holder(recordedIn: holderFile))

        #expect(getpgid(holder) == launched)
        #expect(kill(holder, 0) == 0)
        #expect(outcome.exitCode == 128 + SIGTERM)
        #expect(outcome.stoppedTest?.lines == ["✘ swift test did not exit 0.3 s after its test process ended; stopped it"])
        #expect(outcome.heldOutput?.holders.map(\.pid).contains(holder) == true)
        #expect(outcome.heldOutput?.holders.map(\.pid).contains(launched) == false)
    }

    /// A command that ignores the SIGTERM takes the SIGKILL once the grace has passed.
    @Test(.timeLimit(.minutes(2)))
    func aStoppedSwiftTestThatIgnoresTheTerminationTakesTheKill() throws {
        let root = try TemporaryDirectory.make("run-stall-launch-kill")
        defer { try? FileManager.default.removeItem(at: root) }
        let swift = try Self.standIn(in: root, before: "trap '' TERM")

        let outcome = try Self.run(swift, in: root, killAfter: 0.3) { _ in }

        #expect(outcome.exitCode == 128 + SIGKILL)
        #expect(outcome.stoppedTest != nil)
    }

    /// A command that exits 0 on the SIGTERM it was sent exited by itself as far as the answer goes: never reported stopped, its 0 never turned into the signal's code.
    @Test(.timeLimit(.minutes(2)))
    func aStoppedSwiftTestThatExitsZeroIsNotReportedStopped() throws {
        let root = try TemporaryDirectory.make("run-stall-launch-zero")
        defer { try? FileManager.default.removeItem(at: root) }
        // Perl, like the `sleep` the other stand-ins become, never reaps the `xctest`, and it exits 0 on the SIGTERM.
        let swift = try Self.standIn(in: root, before: "", then: "exec /usr/bin/perl -e '$SIG{TERM} = sub { exit 0 }; sleep 20; exit 3'")

        let outcome = try Self.run(swift, in: root, killAfter: 120) { _ in }

        #expect(outcome.exitCode == 0)
        #expect(outcome.stoppedTest == nil)
    }

    /// A stand-in `swift` in `root`: it runs `before`, starts an `xctest` that lives a second, then runs `then`, by default becoming a `sleep` that never reaps it.
    private static func standIn(in root: URL, before: String, then: String = "exec /bin/sleep 20") throws -> URL {
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let xctest = bin.appendingPathComponent("xctest")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: xctest.path)
        let swift = bin.appendingPathComponent("swift")
        try "#!/bin/sh\necho 'Building for debugging...'\n\(before)\n'\(xctest.path)' 1 &\n\(then)\n".write(to: swift, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swift.path)
        return swift
    }

    /// Runs `swift test` through the stand-in with small injected windows and no crash reports to read.
    private static func run(_ swift: URL, in root: URL, killAfter: TimeInterval, launched: @escaping (Int32) -> Void) throws -> RunOutcome {
        let reports = root.appendingPathComponent("reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let stall = RunTestStall(quiet: 0.3, look: 0.05, killAfter: killAfter, crashReports: RunCrashReports(directory: reports, shownAs: "~"))
        return try RunLauncher(workingDirectory: root, repositoryRoot: nil, runLogDirectory: root).run(
            [swift.path, "test"],
            environment: ProcessEnvironment.withoutGit(),
            patience: patience,
            stall: stall,
            launched: launched
        )
    }

    private static func holder(recordedIn file: URL) -> Int32? {
        (try? String(contentsOf: file, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func endHolder(recordedIn file: URL) {
        if let pid = holder(recordedIn: file) {
            kill(pid, SIGKILL)
        }
    }
}
