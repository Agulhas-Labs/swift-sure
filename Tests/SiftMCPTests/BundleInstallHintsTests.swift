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

/// A release-tarball install on a machine where `claude` is not on PATH: `swift-sure doctor` names the manual registration instead of a `swift-sure install` that cannot run, and `swift-sure install` says a rule `install.sh` already put there is left as installed.
@Suite(.temporaryDirectories)
struct BundleInstallHintsTests {
    private static var notOnPath: String {
        "claude is not on PATH, so `swift-sure install` cannot register the server: run `claude mcp add --transport stdio --scope user swift-sure -- "
    }

    /// `swift-sure doctor --agent claude` over a scratch home with a Claude Code directory and nothing registered.
    private static func doctor(onPath: Set<String>) throws -> (printed: String, status: Int32) {
        let machine = try InstallCommandHarness(onPath: onPath, directories: [".claude"])
        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse(["--agent", "claude"])
        command.output = recorded.output
        command.machine = machine.machine
        do {
            try command.run()
        } catch let exit as ExitCode {
            return (recorded.printed, exit.rawValue)
        }
        return (recorded.printed, 0)
    }

    /// A scratch machine whose binary has no `SwiftSure.md` beside it, with the rule at the destination already there or not.
    private static func bundleless(ruleInstalled: Bool) throws -> InstallCommandHarness {
        let machine = try InstallCommandHarness(onPath: ["claude"], directories: [".claude/rules"])
        try FileManager.default.removeItem(at: machine.bin.appendingPathComponent("SwiftSure.md"))
        if ruleInstalled {
            try "# installed by install.sh\n".write(to: AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: machine.environment), atomically: true, encoding: .utf8)
        }
        return machine
    }

    @Test
    func doctorNamesTheManualRegistrationWhereClaudeIsNotOnPath() throws {
        let run = try Self.doctor(onPath: [])

        #expect(run.status == 1)
        #expect(run.printed.contains("claude server: fail — no MCP server named swift-sure of this tool's in "), "\(run.printed)")
        #expect(run.printed.contains(Self.notOnPath), "\(run.printed)")
        #expect(!run.printed.split(separator: "\n").contains { $0.hasPrefix("claude server:") && $0.contains("swift-sure install --agent claude") }, "\(run.printed)")
    }

    @Test
    func doctorKeepsTheInstallHintWhereClaudeIsOnPath() throws {
        let run = try Self.doctor(onPath: ["claude"])

        #expect(run.status == 1)
        #expect(run.printed.contains("claude server: fail — no MCP server named swift-sure of this tool's in "), "\(run.printed)")
        #expect(run.printed.contains("; run `swift-sure install --agent claude`"), "\(run.printed)")
        #expect(!run.printed.contains("is not on PATH, so"), "\(run.printed)")
    }

    @Test
    func doctorQuotesAPathWithASpaceAndWrapsTheCommandInBackticks() throws {
        let home = try TemporaryDirectory.make("doctor-space")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude", isDirectory: true), withIntermediateDirectories: true)
        let probe = try DoctorProbe(tool: .sift, version: SiftVersion.current, environment: [:])
        probe.close()
        var doctor = DoctorClaude(environment: InstallCommandHarness.environment(home: home), probe: probe, hooks: SiftClaudeSetup.hooks, server: SiftClaudeSetup.server, expectedTools: MCPToolCatalog.toolNames)
        doctor.manualRegistration = SiftClaudeSetup.server.manual(binary: "/Applications/My Tools/swift-sure")

        let line = try #require(doctor.checks().map(\.line).first { $0.hasPrefix("claude server:") })

        #expect(line.contains("run `claude mcp add --transport stdio --scope user swift-sure -- '/Applications/My Tools/swift-sure' mcp` where claude is"), "\(line)")
    }

    @Test
    func aDryRunWithClaudeOffPathSaysWhatTheInstallWouldDo() throws {
        let machine = try InstallCommandHarness(onPath: [], directories: [".claude"])
        let run = try machine.run(["--dry-run", "--agent", "claude"])
        let hint = "`claude` is not on PATH — register the server with: claude mcp add --transport stdio --scope user swift-sure -- \(machine.binary) mcp"

        #expect(run.lines.contains("Claude Code MCP server: \(hint)"), "\(run.printed)")
        #expect(run.printed.contains("would not write \(AgentPaths.claudeConfig(environment: machine.environment).path)"), "\(run.printed)")
        #expect(!run.printed.contains("would register"), "\(run.printed)")
        #expect(!run.printed.contains("would write \(AgentPaths.claudeConfig(environment: machine.environment).path)"), "\(run.printed)")
    }

    @Test
    func aDryRunWithAStaleRegistrationAndClaudeOffPathNamesTheRemovalFirst() throws {
        let machine = try InstallCommandHarness(onPath: [], directories: [".claude"])
        let servers: [String: Any] = ["swift-sure": ["type": "stdio", "command": "/old/bin/swift-sure", "args": ["mcp"]]]
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: machine.home.appendingPathComponent(".claude.json"))
        let run = try machine.run(["--dry-run", "--agent", "claude"])
        let hint = "`claude` is not on PATH — replace the stale registration (/old/bin/swift-sure mcp) with: claude mcp remove swift-sure --scope user; claude mcp add --transport stdio --scope user swift-sure -- \(machine.binary) mcp"

        #expect(run.lines.contains("Claude Code MCP server: \(hint)"), "\(run.printed)")
        #expect(run.printed.contains("would not write \(AgentPaths.claudeConfig(environment: machine.environment).path) (the MCP server at user scope, through `claude mcp add`) — \(hint)"), "\(run.printed)")
    }

    @Test
    func aDryRunWithClaudeOnPathStillSaysItWouldRegisterThroughClaude() throws {
        let machine = try InstallCommandHarness(onPath: ["claude"], directories: [".claude"])
        let run = try machine.run(["--dry-run", "--agent", "claude"])

        #expect(run.lines.contains("Claude Code MCP server: would register \(machine.binary) mcp through `claude mcp add`"), "\(run.printed)")
        #expect(run.printed.contains("would write \(AgentPaths.claudeConfig(environment: machine.environment).path)"), "\(run.printed)")
        #expect(!run.printed.contains("is not on PATH"), "\(run.printed)")
    }

    @Test
    func aDryRunSaysAnInstalledRuleIsLeftAsInstalled() throws {
        let machine = try Self.bundleless(ruleInstalled: true)
        let run = try machine.run(["--dry-run"])
        let reason = "no SwiftSure.md ships beside this binary to refresh it from (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)"

        #expect(run.lines.contains("Claude Code rule: left as installed — \(reason)"), "\(run.printed)")
        #expect(run.printed.contains("left as installed \(AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: machine.environment).path) (the agent rule) — \(reason)"), "\(run.printed)")
        #expect(!run.printed.contains("would be skipped"), "\(run.printed)")
    }

    @Test
    func aDryRunSaysAMissingRuleWouldBeSkipped() throws {
        let machine = try Self.bundleless(ruleInstalled: false)
        let run = try machine.run(["--dry-run"])
        let reason = "no SwiftSure.md ships with this binary (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)"

        #expect(run.lines.contains("Claude Code rule: would be skipped — \(reason)"), "\(run.printed)")
        #expect(run.printed.contains("would be skipped \(AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: machine.environment).path) (the agent rule) — \(reason)"), "\(run.printed)")
        #expect(reason.hasSuffix("(install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)"))
    }

    @Test
    func theInstallSaysAnInstalledRuleIsLeftAsInstalledAndLeavesItAlone() throws {
        let machine = try Self.bundleless(ruleInstalled: true)
        let rule = AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: machine.environment)
        let run = try machine.run(["--yes"])

        #expect(run.printed.contains("rule: left as installed — no SwiftSure.md ships beside this binary to refresh it from (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)"), "\(run.printed)")
        #expect(try String(contentsOf: rule, encoding: .utf8) == "# installed by install.sh\n")
    }

    @Test
    func theInstallSaysAMissingRuleIsSkipped() throws {
        let machine = try Self.bundleless(ruleInstalled: false)
        let run = try machine.run(["--yes"])

        #expect(run.printed.contains("rule: skipped — no SwiftSure.md ships with this binary (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)"), "\(run.printed)")
        #expect(PathKind.of(AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: machine.environment)) == .absent)
    }
}
