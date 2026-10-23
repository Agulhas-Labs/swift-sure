//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure install --dry-run` names the earlier release's server and rule the real install would take out, as the install itself decides it.
@Suite(.temporaryDirectories)
struct InstallDryRunLegacyServerTests {
    /// A scratch machine with `onPath` on the PATH, `server` registered at user scope under the earlier name, and the earlier release's rule beside where the current one goes.
    private static func machine(onPath: Set<String>, server: [String: Any]) throws -> (machine: InstallCommandHarness, rule: URL) {
        let machine = try InstallCommandHarness(onPath: onPath)
        let config = AgentPaths.claudeConfig(environment: machine.environment)
        try JSONSerialization.data(withJSONObject: ["mcpServers": ["sift": server]]).write(to: config)
        let rules = AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: machine.environment).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        let rule = rules.appendingPathComponent("sift.md")
        try Data("the earlier rule\n".utf8).write(to: rule)
        return (machine, rule)
    }

    private static var npxServer: [String: Any] {
        ["type": "stdio", "command": "npx", "args": ["-y", "@agulhas-labs/sift", "mcp"]]
    }

    @Test
    func aDryRunNamesTheEarlierServerAndRuleTheInstallWouldRemove() throws {
        let (machine, rule) = try Self.machine(onPath: ["claude"], server: Self.npxServer)
        let before = try machine.files()

        let run = try machine.run(["--dry-run"])

        #expect(run.status == 0)
        #expect(run.lines.contains("mcp: would remove the user-scope server sift an earlier release registered — npx -y @agulhas-labs/sift mcp"), "\(run.printed)")
        #expect(run.lines.contains("rule: would remove \(rule.path), which an earlier release installed"), "\(run.printed)")
        #expect(try machine.files() == before)
        #expect(machine.claude.calls.isEmpty)
    }

    @Test
    func aDryRunSaysNothingOfAServerNamedSiftThatRunsSomethingElse() throws {
        let (machine, _) = try Self.machine(onPath: ["claude"], server: ["type": "stdio", "command": "/opt/other/sift-helper", "args": ["serve"]])

        let run = try machine.run(["--dry-run"])

        #expect(run.status == 0)
        #expect(!run.printed.contains("user-scope server sift"), "\(run.printed)")
    }

    /// A stale registration of the current name is still this tool's, so the cleanup goes ahead and only the missing `claude` stops it.
    @Test
    func aStaleCurrentServerWithoutClaudeOnThePathNamesTheRemovalToRun() throws {
        let (machine, _) = try Self.machine(onPath: [], server: Self.npxServer)
        let config = AgentPaths.claudeConfig(environment: machine.environment)
        let servers: [String: Any] = ["sift": Self.npxServer, "swift-sure": ["type": "stdio", "command": "/old/place/swift-sure", "args": ["mcp"]]]
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: config)

        let run = try machine.run(["--dry-run"])

        #expect(run.status == 0)
        #expect(run.lines.contains { $0.hasPrefix("mcp: the user-scope server sift an earlier release registered would not be removed — `claude` is not on PATH; run: claude mcp remove") }, "\(run.printed)")
        #expect(!run.printed.contains("would be left, since"), "\(run.printed)")
    }

    @Test
    func aDryRunSaysTheEarlierServerStaysWhereTheCurrentOneWouldNotBeRegistered() throws {
        let (machine, _) = try Self.machine(onPath: [], server: Self.npxServer)

        let run = try machine.run(["--dry-run"])

        #expect(run.status == 0)
        #expect(run.lines.contains("mcp: the user-scope server sift an earlier release registered would be left, since swift-sure would not be registered"), "\(run.printed)")
        #expect(!run.printed.contains("would remove the user-scope server"), "\(run.printed)")
    }
}
