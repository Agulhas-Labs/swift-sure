//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// The `.bak-swift-sure` copies the uninstall writes beside Cursor's `mcp.json` and `hooks.json` and Codex's `hooks.json` are listed and purged as the settings backup is, so none is left behind unnamed.
@Suite(.temporaryDirectories)
struct UninstallAgentBackupTests {
    private typealias Fixture = UninstallCommandTests

    @Test
    func eachAgentBackupThisRunWroteIsListedWithWhatItHolds() throws {
        let agents = try Self.install()

        let lines = try Self.uninstall(agents, purge: false)

        for (file, holds) in [
            (agents.cursorMcp, "the Cursor MCP servers as they were before this uninstall, swift-sure's server included"),
            (agents.cursorHooks, "the Cursor hooks as they were before this uninstall, swift-sure's hooks included"),
            (agents.codexHooks, "the Codex hooks as they were before this uninstall, swift-sure's hooks included"),
        ] {
            let backup = file.appendingPathExtension("bak-swift-sure")
            #expect(PathKind.of(backup) == .file)
            #expect(lines.contains("backup: \(backup.path) — \(holds); `swift-sure uninstall --purge` deletes it"), "\(lines)")
        }
    }

    @Test
    func purgeDeletesEveryAgentBackupAndTheVerdictNamesThem() throws {
        let agents = try Self.install()

        let lines = try Self.uninstall(agents, purge: true)

        for file in [agents.cursorMcp, agents.cursorHooks, agents.codexHooks] {
            let backup = file.appendingPathExtension("bak-swift-sure")
            #expect(PathKind.of(backup) == .absent)
            #expect(lines.contains("backup: deleted \(backup.path)"), "\(lines)")
        }

        #expect(lines.first?.hasSuffix(", deleted the settings, Cursor MCP servers, Cursor hooks and Codex hooks backups") == true, "\(lines)")
    }

    /// A `hooks.json` linked in from a dotfiles directory is rewritten through the link, so its copy is beside the file the link leads to.
    @Test
    func aSymlinkedAgentFilesBackupIsLookedForBesideItsTarget() throws {
        let agents = try Self.install()
        let dotfiles = agents.installed.home.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("hooks.json")
        try FileManager.default.moveItem(at: agents.cursorHooks, to: target)
        try FileManager.default.createSymbolicLink(at: agents.cursorHooks, withDestinationURL: target)
        let backup = URL(fileURLWithPath: CanonicalPath.of(target.path)).appendingPathExtension("bak-swift-sure")

        let lines = try Self.uninstall(agents, purge: false)

        #expect(lines.contains("backup: \(backup.path) — the Cursor hooks as they were before this uninstall, swift-sure's hooks included; `swift-sure uninstall --purge` deletes it"), "\(lines)")
    }
}

extension UninstallAgentBackupTests {
    /// The Claude Code home the uninstall fixture writes, with this tool installed into a Cursor directory and a Codex home inside it.
    struct Agents {
        let installed: UninstallCommandTests.Installed
        let cursor: URL
        let codex: CodexInstall.Home
        let runner: FakeCodex

        var cursorMcp: URL {
            cursor.appendingPathComponent(CursorMcpFile.fileName)
        }

        var cursorHooks: URL {
            cursor.appendingPathComponent(CursorHooksFile.fileName)
        }

        var codexHooks: URL {
            codex.directory.appendingPathComponent(CodexHooksFile.fileName)
        }
    }

    static func install() throws -> Agents {
        let installed = try Fixture.install()
        let cursor = installed.home.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        let codex = CodexInstall.Home(directory: installed.home.appendingPathComponent(".codex"), source: "--codex-dir")
        let runner = FakeCodex()
        _ = try SiftCursorSetup.install.install(directory: cursor, binary: "/bin/swift-sure", binaryWord: "/bin/swift-sure")
        _ = try CodexInstall.install(home: codex, binary: "/bin/swift-sure", binaryWord: "/bin/swift-sure", runner: runner)
        return Agents(installed: installed, cursor: cursor, codex: codex, runner: runner)
    }

    static func uninstall(_ agents: Agents, purge: Bool) throws -> [String] {
        let installed = agents.installed
        let locations = SiftUninstall.Locations(
            settings: installed.settings,
            claudeConfig: installed.claudeConfig,
            rule: installed.rule,
            siftHome: installed.siftHome,
            logs: [installed.siftHome.appendingPathComponent("usage.jsonl")],
            cursor: agents.cursor,
            codex: agents.codex
        )
        let remover = Fixture.ServerRemover()
        return try SiftUninstall.run(locations, purge: purge, binary: "/bin/swift-sure", codex: agents.runner) { scope in
            remover.remove(from: installed.claudeConfig, scope: scope)
        }.lines
    }
}
