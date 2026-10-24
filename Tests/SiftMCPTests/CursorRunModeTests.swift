//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import SiftMCP
import Testing

/// Run mode in Cursor: `install-hook --agent cursor --run-only` registers the build and test hooks alone, a re-run switches either way, the uninstall takes out both sets, and `doctor` and the dry run read the mode.
@Suite(.temporaryDirectories)
struct CursorRunModeTests {
    @Test
    func aRunInstallFromEmptyWritesExactlyTheRunSetAndNoServer() throws {
        let scratch = try TemporaryDirectory.make("cursor-run-empty")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let cursor = scratch.appendingPathComponent(".cursor")

        let printed = try Self.install(cursor, binary: binary, runOnly: true)

        #expect(!FileManager.default.fileExists(atPath: cursor.appendingPathComponent("mcp.json").path))
        let hooks = try #require(CursorInstallHookTests.object(at: cursor.appendingPathComponent("hooks.json"))["hooks"] as? [String: [[String: String]]])
        let word = ShellWord.quoted(binary.path)
        #expect(hooks["preToolUse"] == [["command": "\(word) pre-tool-use --run-only --agent cursor"]])
        #expect(hooks["postToolUse"] == [["command": "\(word) post-tool-use --run-only --agent cursor"]])
        #expect(hooks["postToolUseFailure"] == [["command": "\(word) post-tool-use --run-only --agent cursor"]])
        #expect(hooks["sessionStart"] == nil)
        #expect(printed.contains("hooks: registered preToolUse — \(word) pre-tool-use --run-only --agent cursor\n"), "\(printed)")
        #expect(printed.contains(SiftCursorSetup.runModeLine + "\n"), "\(printed)")
    }

    @Test
    func switchingIndexToRunLeavesOneRunPreToolUseEntryAndNoServerOrSessionStart() throws {
        let scratch = try TemporaryDirectory.make("cursor-run-switch")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let cursor = try CursorInstallHookTests.cursorDirectory(in: scratch, servers: #"{"mcpServers":{"notes":{"args":["serve"],"command":"/opt/notes/bin/notes"}}}"#, hooks: #"{"hooks":{"preToolUse":[{"command":"/usr/local/bin/audit-log.sh"}]},"version":1}"#)
        try Self.install(cursor, binary: binary, runOnly: false)

        let printed = try Self.install(cursor, binary: binary, runOnly: true)

        let servers = try #require(CursorInstallHookTests.object(at: cursor.appendingPathComponent("mcp.json"))["mcpServers"] as? [String: Any])
        #expect(Set(servers.keys) == ["notes"])
        let hooks = try #require(CursorInstallHookTests.object(at: cursor.appendingPathComponent("hooks.json"))["hooks"] as? [String: [[String: String]]])
        let commands = (hooks["preToolUse"] ?? []).compactMap { $0["command"] }
        #expect(commands.count { $0.contains("swift-sure") } == 1, "\(commands)")
        #expect(commands.contains { $0.hasSuffix("pre-tool-use --run-only --agent cursor") })
        #expect(commands.contains("/usr/local/bin/audit-log.sh"))
        #expect(hooks["sessionStart"] == nil)
        #expect(printed.contains("mcp: removed swift-sure — \(binary.path) mcp\n"), "\(printed)")
        #expect(printed.contains("hooks: removed sessionStart"), "\(printed)")
    }

    @Test
    func switchingRunToIndexRestoresExactlyWhatAFreshIndexInstallWrites() throws {
        let scratch = try TemporaryDirectory.make("cursor-run-restore")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let switched = scratch.appendingPathComponent("switched")
        let fresh = scratch.appendingPathComponent("fresh")
        try Self.install(switched, binary: binary, runOnly: true)
        try Self.install(switched, binary: binary, runOnly: false)
        try Self.install(fresh, binary: binary, runOnly: false)

        for file in ["mcp.json", "hooks.json"] {
            #expect(try Data(contentsOf: switched.appendingPathComponent(file)) == Data(contentsOf: fresh.appendingPathComponent(file)), Comment(rawValue: file))
        }

        let again = try Self.install(switched, binary: binary, runOnly: false)

        #expect(again.contains("already registered"))
    }

    @Test
    func aRunReinstallChangesNothingAndWritesNoBackup() throws {
        let scratch = try TemporaryDirectory.make("cursor-run-idempotent")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let cursor = scratch.appendingPathComponent(".cursor")
        try Self.install(cursor, binary: binary, runOnly: true)
        let before = try InstallCommandHarness.files(under: cursor)

        let printed = try Self.install(cursor, binary: binary, runOnly: true)

        #expect(try InstallCommandHarness.files(under: cursor) == before)
        #expect(printed.contains("hooks: already registered — preToolUse, postToolUse, postToolUseFailure\n"), "\(printed)")
        #expect(!printed.contains("restart Cursor"), "\(printed)")
    }

    @Test
    func theUninstallAfterARunInstallLeavesNoEntryOfOurs() throws {
        let scratch = try TemporaryDirectory.make("cursor-run-uninstall")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let cursor = try CursorInstallHookTests.cursorDirectory(in: scratch, servers: nil, hooks: #"{"hooks":{"preToolUse":[{"command":"/usr/local/bin/audit-log.sh"}]},"version":1}"#)
        try Self.install(cursor, binary: binary, runOnly: true)

        let printed = try CursorInstallHookTests.uninstall(cursor)

        let hooks = try #require(CursorInstallHookTests.object(at: cursor.appendingPathComponent("hooks.json"))["hooks"] as? [String: [[String: String]]])

        #expect(hooks == ["preToolUse": [["command": "/usr/local/bin/audit-log.sh"]]])
        #expect(printed.contains("hooks: removed preToolUse"), "\(printed)")
        #expect(try SiftCursorSetup.mode(of: Data(contentsOf: cursor.appendingPathComponent("hooks.json"))) == .index)
    }

    @Test
    func doctorPassesARunInstallWithTheIndexLineAndNoServerFailure() throws {
        let built = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle").path
        let home = try TemporaryDirectory.make("doctor-cursor-run-home")
        let cursor = home.appendingPathComponent(".cursor", isDirectory: true)
        try SiftCursorSetup.install(directory: cursor, binary: built, mode: .run)
        var environment = InstallCommandHarness.environment(home: home)
        environment["PATH"] = "/usr/bin:/bin"
        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse([])
        command.output = recorded.output
        command.machine = AgentDetection.Machine(environment: environment, applications: home, pathLookup: { _ in nil })

        try command.run()

        let lines = recorded.printed.split(separator: "\n").map(String.init)
        #expect(lines.first?.hasPrefix("doctor: passed — 0 of ") == true, "\(recorded.printed)")
        #expect(lines.contains { $0.hasPrefix("cursor index: pass — off (installed with --run-only)") }, "\(recorded.printed)")
        #expect(!lines.contains { $0.hasPrefix("cursor server") }, "\(recorded.printed)")
        for event in SiftCursorSetup.runHooks.hooks.map(\.event) {
            #expect(lines.contains { $0.hasPrefix("cursor hook \(event): pass") }, "\(event) in \(recorded.printed)")
        }
    }

    @Test
    func aDryRunNamesTheCursorMode() throws {
        let machine = try InstallCommandHarness(onPath: [], directories: [".cursor"])

        let run = try machine.run(["--dry-run", "--agent", "cursor", "--run-only"])
        let index = try machine.run(["--dry-run", "--agent", "cursor"])

        #expect(run.lines.contains { $0.hasPrefix("Cursor mode: run (--run-only)") }, "\(run.printed)")
        #expect(index.lines.contains { $0.hasPrefix("Cursor mode: index") }, "\(index.printed)")
        #expect(try machine.files().isEmpty)
    }

    @Test
    func installRunOnlyRegistersTheRunSetInCursor() throws {
        let machine = try InstallCommandHarness(onPath: [], directories: [".cursor"])

        #expect(try machine.run(["--yes", "--agent", "cursor", "--run-only"]).status == 0)

        let hooks = machine.home.appendingPathComponent(".cursor/hooks.json")
        #expect(try SiftCursorSetup.mode(of: Data(contentsOf: hooks)) == .run)
        #expect(!FileManager.default.fileExists(atPath: machine.home.appendingPathComponent(".cursor/mcp.json").path))
    }

    @Test
    func aRunInstallOverAnEarlierReleasesInstallLeavesNoLegacyServerOrHooksAndDoctorPasses() throws {
        let built = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle")
        let home = try TemporaryDirectory.make("cursor-run-legacy-home")
        let old = "/opt/old/bin/sift"
        let entries = SiftCursorSetup.hooks.hooks.map { #""\#($0.event)":[{"command":"\#(old) \#(SiftCursorSetup.hooks.registeredSubcommand(for: $0))"}]"# }
        let cursor = try CursorInstallHookTests.cursorDirectory(
            in: home,
            servers: #"{"mcpServers":{"sift":{"command":"\#(old)","args":["mcp"]}}}"#,
            hooks: #"{"hooks":{\#(entries.joined(separator: ","))},"version":1}"#
        )

        let printed = try Self.install(cursor, binary: built, runOnly: true)

        let servers = try CursorInstallHookTests.object(at: cursor.appendingPathComponent("mcp.json"))["mcpServers"] as? [String: Any] ?? [:]
        #expect(servers.isEmpty, "\(servers.keys) \(printed)")
        let hooks = try #require(CursorInstallHookTests.object(at: cursor.appendingPathComponent("hooks.json"))["hooks"] as? [String: [[String: String]]])
        let commands = hooks.values.flatMap { $0.compactMap { $0["command"] } }
        #expect(!commands.isEmpty && commands.allSatisfy { $0.contains("--run-only") && !$0.contains(old) }, "\(commands)")
        #expect(printed.contains("mcp: removed the server sift an earlier release registered"), "\(printed)")
        #expect(!printed.contains("was left"), "\(printed)")

        var environment = InstallCommandHarness.environment(home: home)
        environment["PATH"] = "/usr/bin:/bin"
        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse([])
        command.output = recorded.output
        command.machine = AgentDetection.Machine(environment: environment, applications: home, pathLookup: { _ in nil })
        try command.run()
        #expect(recorded.printed.split(separator: "\n").first?.hasPrefix("doctor: passed") == true, "\(recorded.printed)")
    }

    @Test
    func aMalformedMcpJsonIsRefusedNamingMcpJsonInBothModesAndTheIndexTextIsTheLibrarys() throws {
        let scratch = try TemporaryDirectory.make("cursor-run-malformed")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let cursor = scratch.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        try Data(#"{"mcpServers": []}"#.utf8).write(to: cursor.appendingPathComponent("mcp.json"))
        let mcpPath = cursor.appendingPathComponent("mcp.json").path

        let library = try #require(Self.refusal { try SiftCursorSetup.installer.install(directory: cursor, binary: binary.path) })
        let index = try #require(Self.refusal { try SiftCursorSetup.install(directory: cursor, binary: binary.path, mode: .index) })
        let run = try #require(Self.refusal { try SiftCursorSetup.install(directory: cursor, binary: binary.path, mode: .run) })

        #expect(library.contains(mcpPath) && !library.contains("hooks.json"), "\(library)")
        #expect(index == library, "\(index) vs \(library)")
        #expect(run.contains(mcpPath) && !run.contains("hooks.json"), "\(run)")
    }

    @Test
    func registersAHookIsTrueForARunInstallsHooksJson() throws {
        let scratch = try TemporaryDirectory.make("cursor-run-registers")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let cursor = scratch.appendingPathComponent(".cursor")
        try SiftCursorSetup.install(directory: cursor, binary: binary.path, mode: .run)

        #expect(try SiftCursorSetup.registersAHook(in: Data(contentsOf: cursor.appendingPathComponent("hooks.json"))))
        #expect(!SiftCursorSetup.registersAHook(in: Data(#"{"hooks":{"preToolUse":[{"command":"/usr/local/bin/audit-log.sh"}]}}"#.utf8)))
    }

    /// What `body` throws, `nil` where it does not.
    private static func refusal(_ body: () throws -> some Any) -> String? {
        do {
            _ = try body()
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// Runs `install-hook --agent cursor` (with `--run-only` when asked) against `directory`, returning what it printed.
    @discardableResult
    private static func install(_ directory: URL, binary: URL, runOnly: Bool) throws -> String {
        var command = try InstallHookCommand.parse(["--agent", "cursor", "--cursor-dir", directory.path] + (runOnly ? ["--run-only"] : []))
        let recorded = RecordedOutput()
        command.output = recorded.output
        command.arguments = [binary.path, "install-hook"]
        command.environment = ["PATH": "/usr/bin:/bin", "CFFIXED_USER_HOME": directory.deletingLastPathComponent().path]
        command.executable = binary.path
        try command.run()
        return recorded.printed
    }
}
