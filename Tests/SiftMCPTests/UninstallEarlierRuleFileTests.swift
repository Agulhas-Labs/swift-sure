//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// A rule file the earlier release installed, `sift.md`, is removed by uninstall and named by the plugin's skip line, though the current name's file is not there.
@Suite(.temporaryDirectories)
struct UninstallEarlierRuleFileTests {
    private typealias Fixture = UninstallCommandTests

    @Test
    func uninstallRemovesTheEarlierRuleAndItsBackup() throws {
        let installed = try Fixture.install()
        let directory = installed.rule.deletingLastPathComponent()
        let earlier = directory.appendingPathComponent("sift.md")
        let backup = directory.appendingPathComponent("sift.md.bak-sift")
        try FileManager.default.removeItem(at: installed.rule)
        try "rule".write(to: earlier, atomically: true, encoding: .utf8)
        try "older".write(to: backup, atomically: true, encoding: .utf8)

        let lines = try Fixture.uninstall(installed, remover: Fixture.ServerRemover())

        #expect(PathKind.of(earlier) == .absent)
        #expect(PathKind.of(backup) == .absent)
        #expect(lines.contains("rule: removed \(earlier.path)"))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("other.md").path))
    }

    @Test
    func theEarlierRuleIsAnInstallerLeftover() throws {
        let home = try TemporaryDirectory.make("earlier-rule-home")
        let rules = home.appendingPathComponent(".claude/rules", isDirectory: true)
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        try "rule".write(to: rules.appendingPathComponent("sift.md"), atomically: true, encoding: .utf8)

        let state = ClaudePluginState(environment: ["HOME": home.path])

        #expect(state.installerLeftovers == ["rule"])
    }

    @Test
    func anotherToolsServerNamedLikeTheEarlierReleaseIsNotALeftover() throws {
        let home = try TemporaryDirectory.make("foreign-server-home")
        let config = #"{"mcpServers":{"sift":{"type":"stdio","command":"/bin/gizmo","args":["serve"]}}}"#
        try config.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let state = ClaudePluginState(environment: ["HOME": home.path])

        #expect(state.installerLeftovers.isEmpty)
    }

    @Test
    func theEarlierReleasesOwnServerIsALeftover() throws {
        let home = try TemporaryDirectory.make("earlier-server-home")
        let config = #"{"mcpServers":{"sift":{"type":"stdio","command":"/bin/sift","args":["mcp"]}}}"#
        try config.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let state = ClaudePluginState(environment: ["HOME": home.path])

        #expect(state.installerLeftovers == ["MCP entry"])
    }
}
