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

/// `swift-sure doctor` on a Claude Code setup where the plugin is enabled.
@Suite(.temporaryDirectories)
struct DoctorPluginTests {
    private static var id: String {
        ProductName.current.word + "@gizmo-market"
    }

    @Test
    func anEnabledPluginWithNothingInstalledPassesWithTheTwoPluginLines() throws {
        let machine = try Self.machine(onPath: true)
        for arguments in [[], ["--agent", "claude"]] {
            let run = try Self.doctor(machine, arguments)
            #expect(run.status == 0, "\(run.printed)")
            #expect(run.printed.contains("claude plugin: pass — \(Self.id) is enabled; hooks, the MCP server and the rule come from it"), "\(run.printed)")
            #expect(run.printed.contains("claude path: pass — "), "\(run.printed)")
            #expect(!run.printed.contains("claude hooks"), "\(run.printed)")
            #expect(!run.printed.contains("claude server"), "\(run.printed)")
        }
    }

    @Test
    func anEarlierInstallsHooksAndRuleAreFlaggedAsRegisteredTwice() throws {
        let machine = try Self.machine(onPath: true, leftovers: ["hooks", "rule"])
        let run = try Self.doctor(machine)
        let binary = ProductName.current.binary

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("claude plugin: fail — registered twice, by the \(binary) plugin and by \(binary) install; run \(binary) uninstall then \(binary) install to keep the plugin, or claude plugin uninstall \(Self.id) to keep the install"), "\(run.printed)")
    }

    @Test
    func onlyTheRuleLeftIsRegisteredTwiceWithNoInstallerChecksAndNoAdviceThatDoesNothing() throws {
        let run = try Self.doctor(Self.machine(onPath: true, leftovers: ["rule"]))

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("claude plugin: fail — registered twice"), "\(run.printed)")
        #expect(run.printed.contains("claude path: pass — "), "\(run.printed)")
        #expect(!run.printed.contains("claude hooks:"), "\(run.printed)")
        #expect(!run.printed.contains("claude server:"), "\(run.printed)")
        #expect(!run.printed.contains("run \(ProductName.current.binary) install"), "\(run.printed)")
    }

    @Test
    func anMCPEntryAloneIsRegisteredTwice() throws {
        let machine = try Self.machine(onPath: true, leftovers: ["MCP entry"])
        #expect(ClaudePluginState(environment: machine.environment).installerLeftovers == ["MCP entry"])

        let run = try Self.doctor(machine)

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("claude plugin: fail — registered twice"), "\(run.printed)")
    }

    @Test
    func aBinaryNotOnPathFailsThePathCheck() throws {
        let run = try Self.doctor(Self.machine(onPath: false))
        let binary = ProductName.current.binary

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("claude path: fail — the \(binary) plugin runs \(binary) from PATH, and \(binary) is not on it; link it into a directory that is"), "\(run.printed)")
    }

    @Test
    func aProjectScopeRecordOrADisabledPluginAddsNoPluginOrPathLine() throws {
        let project = try Self.doctor(Self.machine(onPath: true, scope: "project"))
        let disabled = try Self.doctor(Self.machine(onPath: true, flags: [Self.id: false]))
        for run in [project, disabled] {
            #expect(!run.printed.contains("claude plugin"), "\(run.printed)")
            #expect(!run.printed.contains("claude path"), "\(run.printed)")
            #expect(run.printed.contains("claude: found, swift-sure not installed"), "\(run.printed)")
        }
    }

    /// A scratch home where Claude Code is found and the plugin is recorded, with the parts of an earlier install named in `leftovers` (`hooks`, `MCP entry`, `rule`) still there.
    private static func machine(onPath: Bool, leftovers: [String] = [], scope: String = "user", flags: [String: Bool]? = nil) throws -> AgentDetection.Machine {
        let home = try TemporaryDirectory.make("doctor-plugin-home")
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        if leftovers.contains("hooks") {
            var settings: Data?
            for event in SiftClaudeSetup.events {
                settings = try SiftClaudeSetup.hooks.apply(to: settings, command: "/no/such/place/swift-sure \(event.subcommand)", event: event).data
            }
            try settings?.write(to: claude.appendingPathComponent("settings.json"))
        }
        if leftovers.contains("MCP entry") {
            let servers = [ProductName.current.mcpServer: ["command": "/no/such/place/swift-sure", "args": ["mcp"]]]
            try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: AgentPaths.claudeConfig(environment: InstallCommandHarness.environment(home: home)))
        }
        if leftovers.contains("rule") {
            let rule = AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: InstallCommandHarness.environment(home: home))
            try FileManager.default.createDirectory(at: rule.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "rule\n".write(to: rule, atomically: true, encoding: .utf8)
        }
        try ClaudePluginInstallSkipTests.enable([id], scope: scope, flags: flags, home: home)
        return Self.machine(home: home, onPath: onPath)
    }

    private static func machine(home: URL, onPath: Bool, environment: [String: String]? = nil) -> AgentDetection.Machine {
        let bin = home.appendingPathComponent("bin", isDirectory: true)
        let binary = ProductName.current.binary
        return AgentDetection.Machine(
            environment: environment ?? InstallCommandHarness.environment(home: home),
            applications: home,
            pathLookup: { name in onPath && name == binary ? bin.appendingPathComponent(name) : nil }
        )
    }

    private static func doctor(_ machine: AgentDetection.Machine, _ arguments: [String] = []) throws -> (printed: String, status: Int32) {
        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse(arguments)
        command.output = recorded.output
        command.machine = machine
        do {
            try command.run()
        } catch let exit as ExitCode {
            return (recorded.printed, exit.rawValue)
        }
        return (recorded.printed, 0)
    }
}
