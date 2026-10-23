//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// A `swift-sure run -- xcodebuild test` whose test bundle restarted never takes the inventory's clean form, nor passes `--require-inventory`, even where every declared test reported.
@Suite(.temporaryDirectories)
struct RunRestartedInventoryLineTests {
    private static var marker: String {
        "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
    }

    /// Every declared test reported, `testThree()` on the relaunched pass after the bundle died in it.
    private static var restartedRun: [String] {
        [
            "Test Case '-[GizmoTests.PalletTests testOne]' started.",
            RunInventoryNoteTests.passed("testOne"),
            "Test Case '-[GizmoTests.PalletTests testTwo]' started.",
            RunInventoryNoteTests.passed("testTwo"),
            "Test Case '-[GizmoTests.PalletTests testThree]' started.",
            marker,
            "Test Case '-[GizmoTests.PalletTests testThree]' started.",
            RunInventoryNoteTests.passed("testThree"),
            "Executed 1 test, with 0 failures (0 unexpected) in 0.100 (0.104) seconds",
        ]
    }

    @Test
    func theInventoryLineNamesTheRestart() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (printed, _) = try await Self.run(in: repository, printing: Self.restartedRun, exiting: 65)
        let inventory = printed.split(separator: "\n").filter { $0.hasPrefix("inventory:") }

        #expect(inventory.count == 1)
        #expect(inventory.first?.contains("bundle restarted") == true)
    }

    @Test
    func requireInventoryHoldsARestartedRunUnclean() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (_, thrown) = try await Self.run(in: repository, printing: Self.restartedRun, exiting: 0, flags: ["--require-inventory"])

        #expect(thrown == ExitCode(RunInventoryRequirement.exitCode))
    }

    /// Drives `swift-sure run -- xcodebuild test -scheme gizmo-Package` over a fake `xcodebuild` that prints `lines`, scoped to `repository`, on a thread of its own as ``RunInventoryNoteTests/run(in:printing:exiting:extraArguments:flags:inventoryBudget:bin:emitting:finished:)`` does.
    private static func run(in repository: URL, printing lines: [String], exiting code: Int32, flags: [String] = []) async throws -> (String, ExitCode?) {
        let bin = try TemporaryDirectory.make("run-restart-inventory-bin")
        try (lines.joined(separator: "\n") + "\n").write(to: bin.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        let xcodebuild = bin.appendingPathComponent("xcodebuild")
        try "#!/bin/sh\ncat '\(bin.appendingPathComponent("transcript.txt").path)'\nexit \(code)\n".write(to: xcodebuild, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcodebuild.path)

        let recorded = RecordedOutput()
        let thrown = try await InPlaceAnswerTests.onItsOwnThread {
            Result { () throws -> ExitCode? in
                var command = try RunCommand.parse(flags + ["--", xcodebuild.path, "test", "-scheme", "gizmo-Package"])
                command.log = RunUsageLog(fileURL: bin.appendingPathComponent("run.jsonl"))
                command.writesUnder = repository
                command.output = recorded.output
                command.inventoryBudget = RunInventoryNoteTests.inventoryBudgetForFixtures
                command.hintBudget = RunInventoryNoteTests.inventoryBudgetForFixtures
                do {
                    try command.run()
                    return nil
                } catch let exit as ExitCode {
                    return exit
                }
            }
        }.get()
        return (recorded.printed, thrown)
    }
}
