//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Run mode in Codex: the shell hooks alone, and the install, uninstall and mode reading that move between it and the full set, with the earlier names' leftovers settled.
public extension SiftCodexSetup {
    /// The mode the `hooks.json` bytes `data` hold: run where it registers this tool's run-mode `PreToolUse` handler, index otherwise.
    static func mode(of data: Data?) -> SiftClaudeSetup.InstallMode {
        guard let hook = runHooksFile.hooks.first(where: { $0.event == "PreToolUse" }) else { return .index }
        return runHooksFile.commands(in: data, for: hook).isEmpty ? .index : .run
    }

    /// Puts `mode`'s hooks in `data` and takes the other mode's handlers of ours out, so the file never holds two `PreToolUse` handlers of ours; an event both modes register has our handler rewritten where it sits, so no group or handler changes position, a new group goes after the foreign ones, and a file already in `mode` is unchanged.
    static func mergeHooks(into data: Data?, binaryWord: String, mode: SiftClaudeSetup.InstallMode) throws -> CodexHooksFile.Change {
        let wanted = hooksFile(of: mode)
        let other = hooksFile(of: mode.other)
        let applied = try wanted.apply(to: data, binaryWord: binaryWord, replacing: other.hooks)
        let kept = Set(wanted.hooks.map(\.event))
        let leftover = CodexHooksFile(tool: .sift, hooks: other.hooks.filter { !kept.contains($0.event) })
        let dropped = try leftover.remove(from: applied.changed ? applied.data : data)
        return CodexHooksFile.Change(data: dropped.changed ? dropped.data : applied.data, changed: dropped.changed || applied.changed, replaced: applied.replaced, removed: dropped.removed)
    }

    /// Takes this tool's handlers of both modes out of `data`, as the uninstall does.
    static func removeEitherMode(from data: Data?) throws -> CodexHooksFile.Change {
        let index = try hooksFile.remove(from: data)
        let run = try runHooksFile.remove(from: index.changed ? index.data : data)
        return CodexHooksFile.Change(data: run.changed ? run.data : index.data, changed: index.changed || run.changed, replaced: [], removed: index.removed + run.removed)
    }

    /// Registers the hooks and the server in `home` for `binary`, an absolute path, the same path shell-quoted as the first word of each hook's command.
    ///
    /// `mode` is the set registered: index by default, or run mode, which registers the shell hooks alone and takes our server out through `runner`. Either way the other mode's handlers of ours are taken out in the same write of `hooks.json`, so a re-run switches modes.
    static func install(home: AgentPaths.CodexHome, binary: String, binaryWord: String, runner: any CodexMcpRunner, mode: SiftClaudeSetup.InstallMode = .index) throws -> InstallOutcome {
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let original = try SettingsFile.read(hooksURL, agent: agent, flag: CodexInstall.directoryFlag)
        let hooks = try SettingsFile.merge(hooksURL, agent: agent) { try mergeHooks(into: original, binaryWord: binaryWord, mode: mode) }
        // Codex refuses a CODEX_HOME that is not there, so the directory is made before it is asked anything.
        try CodexInstall.makeHome(home)
        let found = try server.find(runner: runner, home: home.directory)

        var outcome = InstallOutcome(lines: [], notes: [], written: [])
        if mode == .run {
            outcome.lines.append("run mode — index off; re-run without --run-only for the lookup tools")
        }
        outcome.lines += CodexInstall(hooks: hooksFile(of: mode), server: server).hookLines(hooks, original: original, binaryWord: binaryWord)
        try SettingsFile.write(&outcome, hooksURL, hooks.data, original: original, if: hooks.changed, tool: .sift)
        if mode == .index {
            try indexInstall.register(binary, found: found, home: home, runner: runner, into: &outcome)
        } else {
            try indexInstall.unregister(found: found, home: home, runner: runner, noteWithoutCodex: !hooks.removed.isEmpty, into: &outcome)
        }
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
    static func uninstall(home: AgentPaths.CodexHome, runner: any CodexMcpRunner) throws -> InstallOutcome {
        var outcome = InstallOutcome(lines: [], notes: [], written: [])
        guard PathKind.of(home.directory) != .absent else { return outcome }
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let original = try SettingsFile.read(hooksURL, agent: agent, flag: CodexInstall.directoryFlag)
        let hooks = try SettingsFile.merge(hooksURL, agent: agent) { try removeEitherMode(from: original) }
        let found = try server.find(runner: runner, home: home.directory)

        outcome.lines += hooks.removed.map { "hooks: removed \($0)" }
        try SettingsFile.write(&outcome, hooksURL, hooks.data, original: original, if: hooks.changed, tool: .sift)
        try indexInstall.removeServer(found: found, home: home, runner: runner, hooksRemoved: hooks.changed, into: &outcome)
        try settleLegacy(home: home, runner: runner, currentRegistered: nil, into: &outcome)
        return outcome
    }

    /// The install with every line to print for it.
    static func installing(home: AgentPaths.CodexHome, binary: String, runner: any CodexMcpRunner, mode: SiftClaudeSetup.InstallMode = .index) throws -> HookInstallResult {
        let outcome = try install(home: home, binary: binary, binaryWord: ShellWord.quoted(binary), runner: runner, mode: mode)
        return HookInstallResult(outcome: outcome, printed: installer.printed(installing: outcome, home: home))
    }

    /// The uninstall with every line to print for it.
    static func uninstalling(home: AgentPaths.CodexHome, runner: any CodexMcpRunner) throws -> HookInstallResult {
        let outcome = try uninstall(home: home, runner: runner)
        return HookInstallResult(outcome: outcome, printed: installer.printed(uninstalling: outcome, home: home))
    }
}

private extension SiftCodexSetup {
    /// The harness a refusal names.
    static var agent: String {
        "codex"
    }

    /// Takes out, for each earlier name, the hooks and the server this tool registered under it, adding the lines to `outcome`; the flag is whether the install just left the current name's server in place, nil for the uninstall; the last says a server running something else holds the current name.
    ///
    /// Ownership is what the uninstall counts: the earlier name's binary with each hook's subcommand, and the server `codex mcp get` shows running that binary with `mcp`; a server of an earlier name that runs something else is left and unmentioned. For an install, legacy hooks stay when the install reported a failure and the legacy server stays until `codex` shows the current name's server as ours, each with a line naming the install that settles it, so the cleanup never leaves a machine with neither. A `codex` that cannot be asked, or that fails to remove the server, is a line naming the command to run, never a failure.
    static func settleLegacy(home: AgentPaths.CodexHome, runner: any CodexMcpRunner, currentRegistered: Bool?, currentIsForeign: Bool = false, into outcome: inout InstallOutcome) throws {
        let current = ProductName.current
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let installing = currentRegistered != nil
        let installFailed = !outcome.failures.isEmpty
        for name in ProductName.recognised.dropFirst() {
            let original = try SettingsFile.read(hooksURL, agent: agent, flag: CodexInstall.directoryFlag)
            let hooks = try SettingsFile.merge(hooksURL, agent: agent) {
                try CodexHooksFile(tool: SiftClaudeSetup.hooks(named: name).tool, hooks: hooksFile.hooks).remove(from: original)
            }
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
                outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release may have registered could not be checked (\(error)); run: \(CodexInstall.manual(legacy.removeArguments, home: home))")
                continue
            }
            if case .noCodex = found, hooks.changed {
                // The earlier hooks say the earlier release was installed here, so its server most likely was too; without `codex` there is no asking.
                outcome.notes.append("mcp: not checked — `codex` is not on PATH; if Codex runs the earlier release's server \(name.mcpServer), run: \(CodexInstall.manual(legacy.removeArguments, home: home))")
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
                outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release registered was not removed (\(reason)); run: \(CodexInstall.manual(legacy.removeArguments, home: home))")
            }
        }
    }
}
