//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure install --cursor-dir` and `--codex-dir`: the directory each agent's step and dry run write to, and that a flag is never silently ignored.
@Suite(.temporaryDirectories)
struct InstallCommandAgentDirectoryTests {
    /// A scratch directory outside the machine's home, to stand in for the one a flag names.
    private static func elsewhere() throws -> URL {
        try TemporaryDirectory.make("install-agent-directory")
    }

    @Test
    func cursorDirectoryReceivesTheCursorFilesAndTheHomeKeepsNone() throws {
        let machine = try InstallCommandHarness()
        let directory = try Self.elsewhere()

        let run = try machine.run(["--agent", "cursor", "--cursor-dir", directory.path])

        #expect(run.status == 0)
        let written = try InstallCommandHarness.files(under: directory)
        #expect(Set(written.keys) == ["mcp.json", "hooks.json"])
        #expect(try machine.files().keys.contains { $0.hasPrefix(".cursor") } == false)
    }

    @Test
    func codexDirectoryReceivesTheCodexHooksThroughTheInjectedRunner() throws {
        let machine = try InstallCommandHarness()
        let directory = try Self.elsewhere()

        let run = try machine.run(["--agent", "codex", "--codex-dir", directory.path])

        #expect(run.status == 0)
        #expect(try InstallCommandHarness.files(under: directory).keys.contains("hooks.json"))
        #expect(machine.codex.server?.command == machine.binary)
        #expect(try machine.files().keys.contains { $0.hasPrefix(".codex") } == false)
    }

    @Test
    func aDirectoryFlagBesideAnAgentListThatLeavesItOutIsRefused() {
        for (arguments, flag) in [(["--agent", "claude", "--cursor-dir", "/nowhere"], "--cursor-dir"), (["--agent", "cursor", "--codex-dir", "/nowhere"], "--codex-dir")] {
            do {
                _ = try InstallCommand.parse(arguments)
                Issue.record("\(flag) beside \(arguments) was accepted")
            } catch {
                #expect(InstallCommand.message(for: error).contains("\(flag) applies only when"), "\(flag)")
            }
        }
    }

    @Test
    func aDryRunNamesTheFilesOfTheDirectoryTheFlagGives() throws {
        let machine = try InstallCommandHarness()
        let directory = try Self.elsewhere()

        let run = try machine.run(["--dry-run", "--agent", "cursor", "--cursor-dir", directory.path])

        #expect(run.status == 0)
        #expect(run.lines.contains { $0.contains("would write \(directory.path)/mcp.json") })
        #expect(run.lines.contains { $0.contains("would write \(directory.path)/hooks.json") })
        #expect(try InstallCommandHarness.files(under: directory).isEmpty)
    }

    @Test
    func aDirectoryFlagForAnAgentNotFoundIsSaidToBeIgnoredAndWritesNothing() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])
        let directory = try Self.elsewhere()

        let run = try machine.run(["--yes", "--cursor-dir", directory.path])

        #expect(run.lines.contains("note: --cursor-dir applies only to Cursor's install, and Cursor is not being installed, so it was ignored"))
        #expect(try InstallCommandHarness.files(under: directory).isEmpty)
    }

    @Test
    func theInteractiveListNamesTheDirectoryTheFlagGivesNotTheDefault() throws {
        let machine = try InstallCommandHarness(directories: [".cursor"])
        let directory = try Self.elsewhere()

        let run = try machine.run(["--cursor-dir", directory.path], answers: ["y"])

        #expect(run.lines.contains { $0.contains("would write \(directory.path)/mcp.json") })
        #expect(!run.printed.contains("\(machine.home.path)/.cursor/mcp.json"))
        #expect(try InstallCommandHarness.files(under: directory).keys.contains("mcp.json"))
    }

    @Test
    func aDirectoryFlagWhoseAgentWasDeclinedIsSaidToBeIgnored() throws {
        let machine = try InstallCommandHarness(directories: [".cursor"])
        let directory = try Self.elsewhere()

        let run = try machine.run(["--cursor-dir", directory.path], answers: ["n"])

        #expect(run.lines.contains("note: --cursor-dir applies only to Cursor's install, and Cursor is not being installed, so it was ignored"))
        #expect(try InstallCommandHarness.files(under: directory).isEmpty)
    }

    @Test
    func aDryRunSaysAFlagForAnAgentNotFoundHasNoEffect() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])
        let directory = try Self.elsewhere()

        let run = try machine.run(["--dry-run", "--yes", "--cursor-dir", directory.path])

        #expect(run.lines.contains("note: --cursor-dir applies only to Cursor's install, and Cursor is not being installed, so it was ignored"))
    }

    @Test
    func aCodexDryRunNamesTheHooksFileOfTheDirectoryTheFlagGives() throws {
        let machine = try InstallCommandHarness()
        let directory = try Self.elsewhere()

        let run = try machine.run(["--dry-run", "--agent", "codex", "--codex-dir", directory.path])

        #expect(run.status == 0)
        #expect(run.lines.contains { $0.contains("would write \(directory.path)/hooks.json") })
        #expect(try InstallCommandHarness.files(under: directory).isEmpty)
    }

    @Test
    func aCodexDirectoryFlagForAnAgentNotFoundIsSaidToBeIgnored() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])
        let directory = try Self.elsewhere()

        let run = try machine.run(["--yes", "--codex-dir", directory.path])

        #expect(run.lines.contains("note: --codex-dir applies only to Codex's install, and Codex is not being installed, so it was ignored"))
        #expect(try InstallCommandHarness.files(under: directory).isEmpty)
    }

    @Test
    func aDirectoryFlagIsSaidToBeIgnoredWhenNothingIsFoundToInstall() throws {
        let machine = try InstallCommandHarness()
        let directory = try Self.elsewhere()

        let run = try machine.run(["--yes", "--cursor-dir", directory.path])

        #expect(run.lines.contains("note: --cursor-dir applies only to Cursor's install, and Cursor is not being installed, so it was ignored"))
    }
}
