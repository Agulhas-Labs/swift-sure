//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The Claude Code step of `swift-sure install`: the hooks through `install-hook`, which also takes out an older install's status line and band, and asks about the allow rules where `prompt` has a terminal, then the MCP server through `claude mcp`, then the agent rule, then the server and rule an older install registered, which come out only now that the current ones are in place.
struct ClaudeInstallStep {
    /// The binary to install.
    let binary: String

    /// The environment whose home the Claude Code configuration is under.
    let environment: [String: String]

    /// How the binary was invoked, which `install-hook` resolves to ``binary`` again.
    let arguments: [String]

    /// This process's own executable, the other half of how the binary was invoked.
    let executable: String?

    /// Who runs `claude mcp`.
    let runner: any ClaudeMcpRunner

    /// Who answers the allow-rule questions, for the terminal or its absence.
    let prompt: AllowRunPrompt

    /// Both blocks of allow rules, added without asking, as `install-hook --allow-run` does.
    var allowRun = false

    /// The lookups block alone, added without asking, as `install-hook --allow-lookups` does.
    var allowLookups = false

    /// Every name this install answers to, the current one first, which `install-hook` replaces the others' registrations with the current name's for.
    var names = ProductName.recognised

    /// Installs ``binary`` into the Claude Code configuration, printing to `output`.
    func run(output: CommandOutput) throws -> InstallStepReport {
        let plugin = ClaudePluginState(environment: environment)
        if plugin.enabledID != nil {
            output.emit(plugin.installSkipLine)
            return InstallStepReport(agent: .claude)
        }
        // Not named with `--settings`: `install-hook` finds the same file through the environment set below, and only an
        // unnamed file is the user's own, the one `claude plugin` edits, so only then does it take out the legacy band.
        let settings = AgentPaths.claudeSettings(environment: environment)
        var hook = try InstallHookCommand.parse([])
        hook.output = output
        hook.prompt = prompt
        hook.allowRun = allowRun ? true : nil
        hook.allowLookups = allowLookups
        hook.arguments = arguments
        hook.environment = environment
        hook.executable = executable
        hook.names = names
        hook.settlesLegacy = false
        hook.removeLegacyServer = { [runner] _, name, scope in Self.removal(through: runner, arguments: scope.removalArguments(for: name)) }

        var report = InstallStepReport(agent: .claude)
        if try hook.install() {
            report.written.append(SettingsFile.named(settings))
        }
        let server = try SiftClaudeSetup.mcp.install(config: AgentPaths.claudeConfig(environment: environment), binary: binary, runner: runner)
        emit(server, to: output)
        let rule = try SiftClaudeSetup.rule.install(source: SiftClaudeSetup.rule.source(forBinary: binary), destination: AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: environment))
        emit(rule, to: output)
        let settled = hook.settleLegacyRegistrations()
        settled.lines.forEach(output.emit)
        report.written += server.written + rule.written
        report.registered = !server.written.isEmpty || settled.removed
        report.failures = server.failures + rule.failures
        return report
    }

    /// What running `claude` with `arguments` through `runner` came to, as an MCP server removal: the first line of what it printed when it did not succeed.
    private static func removal(through runner: any ClaudeMcpRunner, arguments: [String]) -> SiftUninstall.ServerRemoval {
        do {
            guard let result = try runner.run(arguments) else {
                return .noClaude
            }
            guard result.succeeded else {
                let reason = [result.standardError, result.standardOutput]
                    .compactMap { $0.split(separator: "\n").first.map(String.init) }
                    .first ?? "no output"
                return .failed(reason)
            }
            return .removed
        } catch {
            return .failed("\(error)")
        }
    }

    private func emit(_ outcome: ClaudeInstallOutcome, to output: CommandOutput) {
        for line in outcome.lines + outcome.notes + outcome.failures {
            output.emit(line)
        }
    }
}
