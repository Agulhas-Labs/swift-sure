//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// `install-hook --agent codex` and its inverse: the hooks in the Codex home's `hooks.json`, merged here with the guarantees `settings.json` gets, and the MCP server, registered through `codex mcp` (``CodexMcpServer``).
///
/// The hooks file is read and merged, and the server looked up, before anything is written, so a refusal of either leaves both as they were. Codex runs a hook only once the user has trusted it, and nothing here trusts one on their behalf.
public struct CodexInstall {
    /// The Codex home a run uses and where that came from, which every answer names, since `CODEX_HOME` often points somewhere a person would not look.
    public typealias Home = AgentPaths.CodexHome

    /// What the install output names as not carried over to Codex, one line each.
    public static var unsupported: [String] {
        [
            "unsupported on Codex: \(ProductName.current.binary) audit — Codex's session log is not a documented interface",
            "unsupported on Codex: a Swift-scoped rule — Codex's AGENTS.md applies to every project, so none is written",
            "unsupported on Codex: the subagent primer — no Codex hook for a subagent's start has been verified",
            "unsupported on Codex: the post-edit note for a file apply_patch moves — no payload of a move has been captured",
        ]
    }

    /// The Codex home a run uses: `flag` (`--codex-dir`) when given, else Codex's own rule (``AgentPaths/codexDirectory(environment:)``).
    public static func home(flag: String?, environment: [String: String]) -> Home {
        AgentPaths.codexHome(flag: flag, environment: environment)
    }

    /// Registers the hooks and the server in `home` for `binary`, an absolute path, the same path shell-quoted as the first word of each hook's command.
    public static func install(home: Home, binary: String, binaryWord: String, runner: any CodexMcpRunner) throws -> InstallOutcome {
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let original = try SettingsFile.read(hooksURL, agent: agent, flag: "--codex-dir")
        let hooks = try SettingsFile.merge(hooksURL, agent: agent) { try CodexHooksFile.apply(to: original, binaryWord: binaryWord) }
        // Codex refuses a CODEX_HOME that is not there, so the directory is made before it is asked anything.
        do {
            try FileManager.default.createDirectory(at: home.directory, withIntermediateDirectories: true)
        } catch {
            throw SettingsFile.Refused(path: home.directory.path, reason: "could not be made: \(error.localizedDescription)", agent: "codex")
        }
        let found = try SiftCodexSetup.server.find(runner: runner, home: home.directory)

        var outcome = InstallOutcome(lines: [], notes: [], written: [])
        if hooks.changed {
            outcome.lines += hooks.replaced.map { "hooks: replaced stale registration (\($0))" }
            outcome.lines += CodexHooksFile.hooks.map { "hooks: registered \($0.event) — \(CodexHooksFile.command(for: $0, binaryWord: binaryWord))" }
        } else {
            outcome.lines.append("hooks: already registered — \(CodexHooksFile.hooks.map(\.event).joined(separator: ", "))")
        }
        try SettingsFile.write(&outcome, hooksURL, hooks.data, original: original, if: hooks.changed, tool: .sift)
        try register(binary, found: found, home: home, runner: runner, into: &outcome)
        var registered = outcome.failures.isEmpty
        var foreign = false
        if case .foreign = found {
            registered = false
            foreign = true
        }
        try settleLegacy(home: home, runner: runner, currentRegistered: registered, currentIsForeign: foreign, into: &outcome)
        return outcome
    }

    /// Takes out what the install wrote, and nothing else: a foreign `swift-sure` server and every foreign hook stay, and a Codex home that is not there is not looked into.
    public static func uninstall(home: Home, runner: any CodexMcpRunner) throws -> InstallOutcome {
        var outcome = InstallOutcome(lines: [], notes: [], written: [])
        guard PathKind.of(home.directory) != .absent else { return outcome }
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let original = try SettingsFile.read(hooksURL, agent: agent, flag: "--codex-dir")
        let hooks = try SettingsFile.merge(hooksURL, agent: agent) { try CodexHooksFile.remove(from: original) }
        let found = try SiftCodexSetup.server.find(runner: runner, home: home.directory)

        outcome.lines += hooks.removed.map { "hooks: removed \($0)" }
        try SettingsFile.write(&outcome, hooksURL, hooks.data, original: original, if: hooks.changed, tool: .sift)
        switch found {
        case let .ours(command):
            let removal = try runner.run(SiftCodexSetup.server.removeArguments, home: home.directory)
            if let removal, removal.succeeded {
                outcome.lines.append("mcp: removed \(SiftCursorSetup.mcp.server.name) — \(command) \(SiftCursorSetup.mcp.server.arguments.joined(separator: " "))")
            } else {
                let reason = removal.map(\.failureReason) ?? "`codex` is no longer on PATH"
                outcome.failures.append("mcp: not removed — `codex \(SiftCodexSetup.server.removeArguments.joined(separator: " "))` failed: \(reason); run: \(manual(SiftCodexSetup.server.removeArguments, home: home))")
            }
        case let .foreign(existing):
            outcome.notes.append("mcp: not ours, left alone — a server named \(SiftCursorSetup.mcp.server.name) in \(home.directory.path) runs something else (\(existing))")
        case .noCodex where hooks.changed:
            // The hooks say this tool was installed here, so the server most likely was too; without `codex` there is no asking.
            outcome.notes.append("mcp: not checked — `codex` is not on PATH; if Codex runs this tool's server, run: \(manual(SiftCodexSetup.server.removeArguments, home: home))")
        case .absent, .noCodex:
            break
        }
        try settleLegacy(home: home, runner: runner, currentRegistered: nil, into: &outcome)
        return outcome
    }

    /// Takes out, for each earlier name, the hooks and the server this tool registered under it, adding the lines to `outcome`; the flag is whether the install just left the current name's server in place, nil for the uninstall; the last says a server running something else holds the current name.
    ///
    /// Ownership is what the uninstall counts: the earlier name's binary with each hook's subcommand, and the server `codex mcp get` shows running that binary with `mcp`; a server of an earlier name that runs something else is left and unmentioned. For an install, legacy hooks stay when the install reported a failure and the legacy server stays until `codex` shows the current name's server as ours, each with a line naming the install that settles it, so the cleanup never leaves a machine with neither. A `codex` that cannot be asked, or that fails to remove the server, is a line naming the command to run, never a failure.
    private static func settleLegacy(home: Home, runner: any CodexMcpRunner, currentRegistered: Bool?, currentIsForeign: Bool = false, into outcome: inout InstallOutcome) throws {
        let current = ProductName.current
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let installing = currentRegistered != nil
        let installFailed = !outcome.failures.isEmpty
        for name in ProductName.recognised.dropFirst() {
            let original = try SettingsFile.read(hooksURL, agent: agent, flag: "--codex-dir")
            let hooks = try SettingsFile.merge(hooksURL, agent: agent) { try CodexHooksFile.remove(from: original, registration: SiftClaudeSetup.hooks(named: name)) }
            if hooks.changed, installing, installFailed {
                outcome.lines.append("hooks: the earlier release's hooks (\(name.binary)) were left, since \(current.binary)'s were not all registered; run: \(current.binary) install")
            } else if hooks.changed {
                outcome.lines.append("hooks: removed the earlier release's hooks (\(name.binary))")
                var written = InstallOutcome()
                // The install or uninstall before this already backed the file up from the pre-run bytes; a second backup would overwrite them.
                let alreadyRewritten = outcome.written.contains(SettingsFile.named(hooksURL))
                try SettingsFile.write(&written, hooksURL, hooks.data, original: alreadyRewritten ? nil : original, if: true, tool: .sift)
                outcome.notes += written.notes
                outcome.written += written.written.filter { !outcome.written.contains($0) }
            }
            let legacy = CodexMcpServer(server: SiftClaudeSetup.server(named: name))
            let found: CodexMcpServer.Found
            do {
                found = try legacy.find(runner: runner, home: home.directory)
            } catch {
                outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release may have registered could not be checked (\(error)); run: \(manual(legacy.removeArguments, home: home))")
                continue
            }
            if case .noCodex = found, hooks.changed {
                // The earlier hooks say the earlier release was installed here, so its server most likely was too; without `codex` there is no asking.
                outcome.notes.append("mcp: not checked — `codex` is not on PATH; if Codex runs the earlier release's server \(name.mcpServer), run: \(manual(legacy.removeArguments, home: home))")
            }
            guard case let .ours(command) = found else { continue }
            guard currentRegistered ?? true else {
                if currentIsForeign {
                    outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release registered was left — a server named \(current.mcpServer) runs something else")
                    continue
                }
                outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release registered was left, since \(current.mcpServer) is not registered; run: \(current.binary) install")
                continue
            }
            let removal = try runner.run(legacy.removeArguments, home: home.directory)
            if let removal, removal.succeeded {
                outcome.lines.append("mcp: removed the server \(name.mcpServer) an earlier release registered — \(command) \(legacy.server.arguments.joined(separator: " "))")
            } else {
                let reason = removal.map(\.failureReason) ?? "`codex` is no longer on PATH"
                outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release registered was not removed (\(reason)); run: \(manual(legacy.removeArguments, home: home))")
            }
        }
    }

    /// The harness a refusal names.
    private static var agent: String {
        "codex"
    }

    /// Registers the server unless a foreign one holds the name or ours is already there, and says which.
    private static func register(_ binary: String, found: CodexMcpServer.Found, home: Home, runner: any CodexMcpRunner, into outcome: inout InstallOutcome) throws {
        let name = SiftCursorSetup.mcp.server.name
        let registered = "\(binary) \(SiftCursorSetup.mcp.server.arguments.joined(separator: " "))"
        let arguments = SiftCodexSetup.server.addArguments(binary: binary)
        if case let .foreign(existing) = found {
            return outcome.lines.append("mcp: left alone — a server named \(name) runs something else (\(existing))")
        }
        switch found {
        case .ours(binary):
            return outcome.lines.append("mcp: already registered — \(registered)")
        case let .ours(previous):
            outcome.lines.append("mcp: replaced stale registration (\(previous) \(SiftCursorSetup.mcp.server.arguments.joined(separator: " ")))")
        case .noCodex:
            return outcome.lines.append("mcp: `codex` is not on PATH — register the server with: \(manual(arguments, home: home))")
        case .absent, .foreign:
            break
        }
        let added = try runner.run(arguments, home: home.directory)
        guard let added, added.succeeded else {
            let reason = added.map(\.failureReason) ?? "`codex` is no longer on PATH"
            return outcome.failures.append("mcp: not registered — `codex \(arguments.prefix(3).joined(separator: " "))` failed: \(reason); run: \(manual(arguments, home: home))")
        }
        outcome.lines.append("mcp: registered \(name) — \(registered)")
    }

    /// `codex` with `arguments` as a person pastes it, naming the home in `CODEX_HOME` when it came from `--codex-dir`, where a plain `codex` would not look.
    private static func manual(_ arguments: [String], home: Home) -> String {
        let command = (["codex"] + arguments.map(ShellWord.quoted)).joined(separator: " ")
        guard home.source == "--codex-dir" else { return command }
        return "CODEX_HOME=\(ShellWord.quoted(home.directory.path)) \(command)"
    }
}
