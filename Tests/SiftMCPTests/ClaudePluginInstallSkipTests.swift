//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure install` leaves Claude Code to the plugin where the plugin is enabled, and Cursor and Codex to itself.
@Suite(.temporaryDirectories)
struct ClaudePluginInstallSkipTests {
    private static var skipLine: String {
        "claude: the swift-sure plugin is enabled, so hooks, the MCP server and the rule come from it and are left alone"
    }

    private static func machine() throws -> InstallCommandHarness {
        try InstallCommandHarness(onPath: ["claude", "codex"], directories: [".claude", ".cursor"])
    }

    /// Writes Claude Code's plugin records under `home`'s `.claude`, one record of `scope` for each of `ids`, and `enabledPlugins` into its settings where `flags` is given.
    static func enable(_ ids: [String], scope: String = "user", flags: [String: Bool]? = nil, home: URL) throws {
        let directory = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("plugins", isDirectory: true), withIntermediateDirectories: true)
        let records = Dictionary(uniqueKeysWithValues: ids.map { ($0, [["scope": scope, "version": "1.0.0"]]) })
        try JSONSerialization.data(withJSONObject: ["version": 2, "plugins": records]).write(to: directory.appendingPathComponent("plugins/installed_plugins.json"))
        if let flags {
            try JSONSerialization.data(withJSONObject: ["enabledPlugins": flags]).write(to: directory.appendingPathComponent("settings.json"))
        }
    }

    @Test
    func aUserScopeRecordWithNoSettingsEntryIsEnabledAndSkipsClaudeCode() throws {
        let machine = try Self.machine()
        try Self.enable(["swift-sure@gizmo-market"], home: machine.home)

        let run = try machine.run(["--yes"])

        #expect(run.status == 0)
        #expect(run.lines.contains { $0.hasSuffix(Self.skipLine) }, "\(run.printed)")
        #expect(try machine.files()[".claude/rules/swift-sure.md"] == nil)
    }

    @Test
    func theSkipWritesNoHooksNoServerAndNoRuleAndCursorAndCodexStillInstall() throws {
        let machine = try Self.machine()
        try Self.enable(["swift-sure@gizmo-market"], flags: ["swift-sure@gizmo-market": true], home: machine.home)

        _ = try machine.run(["--yes"])

        let files = try machine.files()
        #expect(files[".claude.json"] == nil)
        #expect(files[".claude/rules/swift-sure.md"] == nil)
        let data = try #require(files[".claude/settings.json"])
        let settings = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(settings["hooks"] == nil)
        #expect(machine.claude.calls.isEmpty)
        #expect(files[".cursor/mcp.json"] != nil)
        #expect(files[".cursor/hooks.json"] != nil)
        #expect(files[".codex/hooks.json"] != nil)
    }

    @Test
    func aRecordSetToFalseInstallsNormally() throws {
        let machine = try Self.machine()
        try Self.enable(["swift-sure@gizmo-market"], flags: ["swift-sure@gizmo-market": false], home: machine.home)

        let run = try machine.run(["--yes"])

        #expect(!run.printed.contains(Self.skipLine))
        #expect(try machine.files()[".claude/rules/swift-sure.md"] != nil)
    }

    @Test
    func aProjectScopeRecordAloneInstallsNormally() throws {
        let machine = try Self.machine()
        try Self.enable(["swift-sure@gizmo-market"], scope: "project", flags: ["swift-sure@gizmo-market": true], home: machine.home)

        let run = try machine.run(["--yes"])

        #expect(!run.printed.contains(Self.skipLine))
        #expect(try machine.files()[".claude/rules/swift-sure.md"] != nil)
    }

    @Test
    func anyMarketplaceCountsAndAnotherPluginDoesNot() throws {
        let machine = try Self.machine()
        try Self.enable(["widget@gizmo-market", "sift-band@sift"], home: machine.home)
        #expect(ClaudePluginState(environment: machine.environment).enabledID == nil)

        try Self.enable(["widget@gizmo-market", "swift-sure@zebra-market", "swift-sure@acme-market"], home: machine.home)
        #expect(ClaudePluginState(environment: machine.environment).enabledID == "swift-sure@acme-market")
    }

    @Test
    func theSummarySaysClaudeCodeIsLeftToThePluginAndLeavesTheOtherAgentsAlone() throws {
        let machine = try Self.machine()
        try Self.enable(["swift-sure@gizmo-market"], home: machine.home)

        let run = try machine.run(["--yes"])

        #expect(run.lines.contains("  Claude Code: left to the swift-sure plugin"), "\(run.printed)")
        #expect(!run.printed.contains("Claude Code: already installed"), "\(run.printed)")
        #expect(run.lines.contains { $0.hasPrefix("  Cursor: installed") }, "\(run.printed)")
        #expect(run.lines.contains { $0.hasPrefix("  Codex: installed") }, "\(run.printed)")
    }

    @Test
    func theConfigurationDirectoryClaudeCodeNamesIsWhereThePluginIsRead() throws {
        let home = try TemporaryDirectory.make("plugin-config-home")
        let elsewhere = try TemporaryDirectory.make("plugin-config-dir")
        try Self.enable(["swift-sure@gizmo-market"], home: elsewhere)
        var environment = InstallCommandHarness.environment(home: home)
        environment["CLAUDE_CONFIG_DIR"] = elsewhere.appendingPathComponent(".claude", isDirectory: true).path

        #expect(ClaudePluginState(environment: environment).enabledID == "swift-sure@gizmo-market")
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path))
        #expect(ClaudePluginState(environment: InstallCommandHarness.environment(home: home)).enabledID == nil)
    }

    @Test
    func aSkipNamesExactlyTheHooksAndRuleAnEarlierInstallLeft() throws {
        let machine = try Self.machine()
        _ = try machine.run(["--yes", "--agent", "claude"])
        try FileManager.default.removeItem(at: machine.home.appendingPathComponent(".claude.json"))
        try Self.enable(["swift-sure@gizmo-market"], home: machine.home)

        let run = try machine.run(["--yes", "--agent", "claude"])

        let expected = Self.skipLine + "; hooks and rule still present from swift-sure install: run swift-sure uninstall, then swift-sure install"

        #expect(run.lines.contains { $0.hasSuffix(expected) }, "\(run.printed)")
        #expect(try machine.files()[".claude/rules/swift-sure.md"] != nil)
    }
}
