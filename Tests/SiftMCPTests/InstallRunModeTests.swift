//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure install` into Claude Code is the full set unless `--run-only` is given: run mode registers the build and test hooks and takes out the server and rule an index install made.
@Suite(.temporaryDirectories)
struct InstallRunModeTests {
    private static func hookEvents(_ machine: InstallCommandHarness, sourceLocation: SourceLocation = #_sourceLocation) throws -> Set<String> {
        let settings = machine.home.appendingPathComponent(".claude/settings.json")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any], sourceLocation: sourceLocation)
        return Set((object["hooks"] as? [String: Any] ?? [:]).keys)
    }

    private static func rule(_ machine: InstallCommandHarness) -> URL {
        machine.home.appendingPathComponent(".claude/rules/swift-sure.md")
    }

    private static func servers(_ machine: InstallCommandHarness) throws -> [String: Any] {
        let config = machine.home.appendingPathComponent(".claude.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        return object?["mcpServers"] as? [String: Any] ?? [:]
    }

    @Test
    func theDefaultInstallsTheServerTheRuleAndThePrimer() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])

        let run = try machine.run(["--yes"])

        #expect(run.status == 0)
        #expect(machine.claude.calls == [SiftClaudeSetup.server.addArguments(binary: machine.binary)])
        #expect(FileManager.default.fileExists(atPath: Self.rule(machine).path))
        #expect(try Self.hookEvents(machine).contains("SessionStart"))
        #expect(try Self.servers(machine)["swift-sure"] != nil)
    }

    @Test
    func runModeRegistersNoServerNoRuleAndNoPrimer() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])

        let run = try machine.run(["--yes", "--run-only"])

        #expect(run.status == 0)
        #expect(!machine.claude.calls.contains { $0.starts(with: ["mcp", "add"]) })
        #expect(!FileManager.default.fileExists(atPath: Self.rule(machine).path))
        let events = try Self.hookEvents(machine)
        #expect(!events.contains("SessionStart"))
        #expect(events.contains("PreToolUse"))
        #expect(!run.printed.contains("--allow-lookups"))
    }

    @Test
    func runModeOverAnIndexInstallRemovesTheServerAndTheRuleThroughTheRunner() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])
        #expect(try machine.run(["--yes"]).status == 0)

        let run = try machine.run(["--yes", "--run-only"])

        #expect(run.status == 0)
        #expect(machine.claude.calls.contains { $0.starts(with: ["mcp", "remove"]) })
        #expect(try Self.servers(machine)["swift-sure"] == nil)
        #expect(!FileManager.default.fileExists(atPath: Self.rule(machine).path))
        #expect(try !Self.hookEvents(machine).contains("SessionStart"))
    }

    @Test
    func runModeLeavesASymlinkedRuleAlone() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])
        let checkout = machine.home.appendingPathComponent("checkout-rule.md")
        try Data("the checkout's rule\n".utf8).write(to: checkout)
        let rule = Self.rule(machine)
        try FileManager.default.createDirectory(at: rule.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: rule, withDestinationURL: checkout)

        let run = try machine.run(["--yes", "--run-only"])

        #expect(run.status == 0)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: rule.path) == checkout.path)
        #expect(try String(contentsOf: checkout, encoding: .utf8) == "the checkout's rule\n")
    }

    @Test
    func allowLookupsWithRunOnlyIsRefused() {
        #expect(throws: (any Error).self) { try InstallCommand.parse(["--yes", "--run-only", "--allow-lookups"]) }
        #expect(throws: Never.self) { try InstallCommand.parse(["--yes", "--allow-lookups"]) }
    }

    @Test
    func aRunModeDryRunSaysTheServerAndRuleWouldBeRemovedAndWritesNothing() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])
        #expect(try machine.run(["--yes"]).status == 0)
        let before = try machine.files()
        let calls = machine.claude.calls

        let run = try machine.run(["--dry-run", "--run-only"])

        #expect(run.status == 0)
        #expect(try machine.files() == before)
        #expect(machine.claude.calls == calls)
        #expect(run.lines.contains { $0.hasPrefix("Claude Code mode: run") })
        #expect(run.lines.contains("Claude Code MCP server: would be removed through `claude mcp remove`"))
        #expect(run.lines.contains("Claude Code rule: would remove \(Self.rule(machine).path)"))
    }

    @Test
    func aRunModeDryRunOnAnEmptyHomeHasNothingToRemove() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])

        let run = try machine.run(["--dry-run", "--run-only"])

        #expect(run.lines.contains("Claude Code MCP server: nothing registered"))
        #expect(run.lines.contains("Claude Code rule: nothing installed"))
        #expect(!run.printed.contains("would register"))
    }

    @Test
    func aDefaultDryRunNamesTheIndexModeAndWouldRegisterTheServer() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"])

        let run = try machine.run(["--dry-run"])

        #expect(run.lines.contains { $0.hasPrefix("Claude Code mode: index") })
        #expect(run.lines.contains("Claude Code MCP server: would register \(machine.binary) mcp through `claude mcp add`"))
        #expect(run.lines.contains("Claude Code rule: would copy SwiftSure.md to \(Self.rule(machine).path)"))
    }
}
