//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// Covers how `swift-sure run` answers for a `swift test` it stopped: the stop is the answer's first line, with the crash report beneath it, and both are counted among what it printed.
@Suite(.temporaryDirectories)
struct RunStoppedTestAnswerTests {
    private static let stopped = RunStoppedTest(
        quiet: 30,
        crash: RunCrashReport(path: "~/Library/Logs/DiagnosticReports/xctest-2026-10-20-092101.ips", exceptionType: "EXC_BAD_ACCESS", signal: "SIGBUS", recursionDepth: 6326)
    )

    /// The answer opens on the stop and the crash report, ahead of everything the filter has to say.
    @Test
    func theAnswerOpensOnTheStopAndTheCrashReport() throws {
        let directory = try TemporaryDirectory.make("run-stopped-answer")
        defer { try? FileManager.default.removeItem(at: directory) }
        let swift = directory.appendingPathComponent("swift")
        try "#!/bin/sh\necho 'Building for debugging...'\necho 'error: boom'\nexit 143\n".write(to: swift, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swift.path)
        let ran = try RunLauncher(workingDirectory: directory, repositoryRoot: nil, runLogDirectory: directory)
            .run([swift.path, "test"], environment: ProcessEnvironment.withoutGit())
        let outcome = RunOutcome(kind: ran.kind, logKey: ran.logKey, exitCode: ran.exitCode, report: ran.report, log: ran.log, repositoryRoot: nil, stoppedTest: Self.stopped)
        let recorded = RecordedOutput()
        var command = try RunCommand.parse(["--", swift.path, "test"])
        command.output = recorded.output

        let shown = command.report(outcome, workingDirectory: directory, accessibility: [], bundles: .undetermined, selector: nil)

        #expect(recorded.printed.hasPrefix(
            "✘ swift test did not exit 30 s after its test process ended; stopped it\n"
                + "crash report: ~/Library/Logs/DiagnosticReports/xctest-2026-10-20-092101.ips — EXC_BAD_ACCESS (SIGBUS), recursion depth 6326\n"
        ))
        #expect(shown == recorded.printed.split(separator: "\n", omittingEmptySubsequences: false).count - 1)
    }

    /// A stopped `swift test --filter …` whose log shows only a compile error and no test exits with the stopped command's own code, never the did-not-build code that log would otherwise earn.
    @Test(.timeLimit(.minutes(2)))
    func aStoppedFilteredRunExitsWithTheSignalsCode() throws {
        let directory = try TemporaryDirectory.make("run-stopped-exit")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let xctest = bin.appendingPathComponent("xctest")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: xctest.path)
        let swift = bin.appendingPathComponent("swift")
        let source = directory.appendingPathComponent("Gadget.swift").path
        try "#!/bin/sh\necho 'Building for debugging...'\necho '\(source):1:1: error: boom'\n'\(xctest.path)' 1 &\nexec /bin/sleep 20\n"
            .write(to: swift, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swift.path)
        let reports = directory.appendingPathComponent("reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let recorded = RecordedOutput()
        var command = try RunCommand.parse(["--", swift.path, "test", "--filter", "GadgetTests"])
        command.log = RunUsageLog(fileURL: bin.appendingPathComponent("run.jsonl"))
        command.writesUnder = directory
        command.output = recorded.output
        command.stall = RunTestStall(quiet: 0.3, look: 0.05, killAfter: 120, crashReports: RunCrashReports(directory: reports, shownAs: "~"))

        #expect(throws: ExitCode(128 + SIGTERM)) {
            try command.run()
        }
        #expect(recorded.printed.hasPrefix("✘ swift test did not exit 0.3 s after its test process ended; stopped it\n"), "\(recorded.printed)")
    }
}
