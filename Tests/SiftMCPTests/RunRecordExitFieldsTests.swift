//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// The records `swift-sure run` files carry the run's argv, and a red one carries the exit code the run exited with and whether SwiftSure stopped it.
@Suite(.temporaryDirectories)
struct RunRecordExitFieldsTests {
    private static func outcome(_ exitCode: Int32, stopped: RunStoppedTest? = nil, in repository: URL) -> RunOutcome {
        RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: exitCode, report: nil, log: nil, repositoryRoot: repository, stoppedTest: stopped)
    }

    @Test
    func aRedRecordCarriesTheArgvTheExitCodeAndNoStop() throws {
        let repository = try TemporaryDirectory.make("run-record-exit-fields").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Self.initialiseRepository(repository)
        let ran = try Self.provable(repository)
        var command = try RunCommand.parse(["--", "swift", "test", "--filter", "Gizmo"])
        command.writesUnder = repository

        command.recordFailure(Self.outcome(1, in: repository), ran: ran, in: repository, milliseconds: 1, exitCode: 4)

        let record = try #require(RunLedger.inRepository(at: repository).failedRuns.records().first)

        #expect(record.arguments == ["swift", "test", "--filter", "Gizmo"])
        #expect(record.exitCode == 4)
        #expect(record.stoppedBySift == false)
    }

    @Test
    func aStoppedRunIsMarkedStoppedAndKeepsTheCommandsOwnCode() throws {
        let repository = try TemporaryDirectory.make("run-record-stopped").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Self.initialiseRepository(repository)
        let ran = try Self.provable(repository)
        var command = try RunCommand.parse(["--", "swift", "test"])
        command.writesUnder = repository
        let stopped = RunStoppedTest(quiet: 30, crash: nil)

        command.recordFailure(Self.outcome(143, stopped: stopped, in: repository), ran: ran, in: repository, milliseconds: 1)

        let record = try #require(RunLedger.inRepository(at: repository).failedRuns.records().first)

        #expect(record.exitCode == 143)
        #expect(record.stoppedBySift == true)
    }

    @Test
    func aGreenRecordCarriesTheArgvAndNoExitCode() throws {
        let repository = try TemporaryDirectory.make("run-record-green-fields").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Self.initialiseRepository(repository)
        let ran = try Self.provable(repository)
        let toolchain = try #require(ToolchainIdentity.current())
        var command = try RunCommand.parse(["--", "swift", "test"])
        command.writesUnder = repository

        let record = command.ledgerRecord(Self.outcome(0, in: repository), ran: ran, in: repository, toolchain: toolchain.description, milliseconds: 1)

        #expect(record.arguments == ["swift", "test"])
        #expect(record.exitCode == nil)
        #expect(record.stoppedBySift == nil)
    }
}

private extension RunRecordExitFieldsTests {
    static func provable(_ repository: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> RunCommand.ProvableRun {
        let tree = try #require(TreeKey.of(repositoryRoot: repository), sourceLocation: sourceLocation)
        return RunCommand.ProvableRun(tree: tree, workingDirectory: ".")
    }

    static func initialiseRepository(_ root: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "struct Gizmo {}\n".write(to: root.appendingPathComponent("Sources/Gizmo.swift"), atomically: true, encoding: .utf8)
        for arguments in [["init", "-q", "-b", "main"], ["add", "-A"], ["-c", "user.email=t@example.com", "-c", "user.name=T", "commit", "-q", "-m", "seed"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.environment = ProcessEnvironment.withoutGit()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, sourceLocation: sourceLocation)
        }
    }
}
