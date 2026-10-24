//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Run mode in Cursor: the build and test hooks alone, and the install, uninstall and mode reading that move between it and the full set.
public extension SiftCursorSetup {
    /// The subcommand the run set's `postToolUse` and `postToolUseFailure` hooks run: it answers a shell call's result alone.
    static var runPostToolUseSubcommand: String {
        "post-tool-use --run-only"
    }

    /// The hooks `--run-only` registers in `hooks.json`: the run-only pre-tool-use hook and the post-tool-use hooks for a shell result, with no session start.
    static let runHooks = CursorHooksFile(
        tool: .sift,
        agentFlag: hooks.agentFlag,
        hooks: [
            CursorHooksFile.Hook(event: "preToolUse", subcommand: SiftClaudeSetup.runOnlyPreToolUseSubcommand),
            CursorHooksFile.Hook(event: "postToolUse", subcommand: runPostToolUseSubcommand),
            CursorHooksFile.Hook(event: "postToolUseFailure", subcommand: runPostToolUseSubcommand),
        ]
    )

    /// Said on a run-mode install, as the Claude Code install says its mode.
    static var runModeLine: String {
        "run mode — index off; re-run without --run-only for the lookup tools"
    }

    /// The hooks of `mode`.
    static func hooks(of mode: SiftClaudeSetup.InstallMode) -> CursorHooksFile {
        mode == .index ? hooks : runHooks
    }

    /// The mode the `hooks.json` bytes `data` hold: run where it registers the run-only pre-tool-use hook, index otherwise.
    static func mode(of data: Data?) -> SiftClaudeSetup.InstallMode {
        guard let hook = runHooks.hooks.first(where: { $0.event == "preToolUse" }) else { return .index }
        let file = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let entries = (file?["hooks"] as? [String: Any])?[hook.event] as? [[String: Any]] ?? []
        let ours = entries.compactMap { $0["command"] as? String }.contains { command in
            FieldworkTool.recognised.contains { $0.runs(command, subcommand: runHooks.registeredSubcommand(for: hook)) }
        }
        return ours ? .run : .index
    }

    /// What an install of one mode does to the two files, composed in memory: the other mode's hooks taken out, this mode's applied, and in run mode the server taken out.
    struct Merge {
        /// What happened to the `mcp.json` server.
        public let server: CursorMcpFile.Change
        /// The `hooks.json` bytes after the install.
        public let hooksData: Data
        /// Whether `hooks.json` differs from what was read.
        public let hooksChanged: Bool
        /// The hooks of the other mode taken out, as `<event> — <command>`.
        public let removed: [String]
        /// The stale commands of ours repointed at this binary.
        public let replaced: [String]
    }

    /// The merge of `mode` over the bytes of `mcp.json` and `hooks.json` (nil where there is no file) for the binary `binary`, spelled `binaryWord` in a shell command.
    ///
    /// A server that cannot be merged is refused naming `mcp.json` in `directory`, and hooks that cannot be, `hooks.json` there.
    static func merge(directory: URL, mcpData: Data?, hooksData: Data?, binary: String, binaryWord: String, mode: SiftClaudeSetup.InstallMode) throws -> Merge {
        let mcpURL = directory.appendingPathComponent(CursorMcpFile.fileName)
        let hooksURL = directory.appendingPathComponent(CursorHooksFile.fileName)
        let server = try SettingsFile.merge(mcpURL, agent: "cursor") { try mode == .index ? mcp.apply(to: mcpData, binary: binary) : mcp.remove(from: mcpData) }
        let (cleared, applied) = try SettingsFile.merge(hooksURL, agent: "cursor") {
            let cleared = try hooks(of: mode.other).remove(from: hooksData)
            return try (cleared, hooks(of: mode).apply(to: cleared.data, binaryWord: binaryWord))
        }
        return Merge(server: server, hooksData: applied.data, hooksChanged: cleared.changed || applied.changed, removed: cleared.removed, replaced: applied.replaced)
    }

    /// Registers `mode`'s set in `directory`, taking out the other mode's, and says what it did as ``CursorHookInstaller`` does.
    ///
    /// An index install of a directory holding no run set writes and says exactly what `installer` does. Each file is written at most once, and not at all where nothing changes.
    @discardableResult
    static func install(directory: URL, binary: String, mode: SiftClaudeSetup.InstallMode) throws -> CursorHookInstallResult {
        let binaryWord = ShellWord.quoted(binary)
        let mcpURL = directory.appendingPathComponent(CursorMcpFile.fileName)
        let hooksURL = directory.appendingPathComponent(CursorHooksFile.fileName)
        let mcpOriginal = try read(mcpURL)
        let hooksOriginal = try read(hooksURL)
        let merged = try merge(directory: directory, mcpData: mcpOriginal, hooksData: hooksOriginal, binary: binary, binaryWord: binaryWord, mode: mode)
        let set = hooks(of: mode)
        let registered = mcp.server.registered(binary: binary)
        var lines: [String] = []
        let name = mcp.server.name
        switch merged.server.outcome {
        case .registered:
            lines.append("mcp: registered \(name) — \(registered)")
        case let .replaced(previous):
            lines.append("mcp: replaced stale registration (\(previous))")
            lines.append("mcp: registered \(name) — \(registered)")
        case .unchanged where mode == .index:
            lines.append("mcp: already registered — \(registered)")
        case let .removed(existing):
            lines.append("mcp: removed \(name) — \(existing)")
        case let .foreign(existing):
            lines.append("mcp: left alone — a server named \(name) runs something else (\(existing))")
        case .unchanged:
            break
        }
        if merged.hooksChanged {
            lines += merged.removed.map { "hooks: removed \($0)" }
            lines += merged.replaced.map { "hooks: replaced stale registration (\($0))" }
            lines += set.hooks.map { "hooks: registered \($0.event) — \(set.command(for: $0, binaryWord: binaryWord))" }
        } else {
            lines.append("hooks: already registered — \(set.hooks.map(\.event).joined(separator: ", "))")
        }
        var outcome = InstallOutcome(lines: lines)
        try SettingsFile.write(&outcome, mcpURL, merged.server.data, original: mcpOriginal, if: merged.server.changed, tool: mcp.server.tool)
        try SettingsFile.write(&outcome, hooksURL, merged.hooksData, original: hooksOriginal, if: merged.hooksChanged, tool: set.tool)
        var printed = outcome.lines + outcome.written.map { "      \($0)" } + outcome.notes
        if outcome.changed {
            printed.append(CursorHookInstaller.restart)
        }
        if mode == .run {
            printed.append(runModeLine)
        }
        printed += unsupported
        printed.append(experimental)
        return CursorHookInstallResult(outcome: outcome, printed: printed)
    }

    /// The Cursor step of `swift-sure install` in `mode`; `directory` overrides the Cursor directory the home `environment` names.
    static func step(mode: SiftClaudeSetup.InstallMode, binary: String, environment: [String: String], directory: String? = nil) throws -> InstallStepReport {
        let target = directory.map { URL(fileURLWithPath: $0) } ?? AgentPaths.cursorDirectory(environment: environment)
        let result = try install(directory: target, binary: binary, mode: mode)
        return InstallStepReport(agent: .cursor, lines: result.printed, written: result.outcome.written, failures: result.outcome.failures)
    }

    /// Takes out what an install of either mode wrote, and nothing else: the server, and the hooks of both sets; a foreign server or hook stays and a file with nothing of ours in it is not rewritten.
    static func uninstall(directory: URL) throws -> InstallOutcome {
        let mcpURL = directory.appendingPathComponent(CursorMcpFile.fileName)
        let hooksURL = directory.appendingPathComponent(CursorHooksFile.fileName)
        let mcpOriginal = try read(mcpURL)
        let hooksOriginal = try read(hooksURL)
        let server = try SettingsFile.merge(mcpURL, agent: "cursor") { try mcp.remove(from: mcpOriginal) }
        let (hooksData, removed) = try SettingsFile.merge(hooksURL, agent: "cursor") {
            let index = try hooks.remove(from: hooksOriginal)
            let run = try runHooks.remove(from: index.data)
            return (run.data, index.removed + run.removed)
        }
        var lines: [String] = []
        var notes: [String] = []
        let name = mcp.server.name
        switch server.outcome {
        case let .removed(existing):
            lines.append("mcp: removed \(name) — \(existing)")
        case let .foreign(existing):
            notes.append("mcp: not ours, left alone — a server named \(name) in \(mcpURL.path) runs something else (\(existing))")
        case .registered, .replaced, .unchanged:
            break
        }
        lines += removed.map { "hooks: removed \($0)" }
        var outcome = InstallOutcome(lines: lines, notes: notes)
        try SettingsFile.write(&outcome, mcpURL, server.data, original: mcpOriginal, if: server.changed, tool: mcp.server.tool)
        try SettingsFile.write(&outcome, hooksURL, hooksData, original: hooksOriginal, if: !removed.isEmpty, tool: hooks.tool)
        return outcome
    }

    /// ``uninstall(directory:)`` with what `swift-sure uninstall-hook --agent cursor` prints around it.
    @discardableResult
    static func uninstaller(directory: URL) throws -> CursorHookInstallResult {
        let outcome = try uninstall(directory: directory)
        var printed: [String] = []
        if outcome.lines.isEmpty {
            printed.append("cursor: nothing registered in \(directory.path)")
        }
        printed += outcome.lines + outcome.written.map { "      \($0)" } + outcome.notes
        if outcome.changed {
            printed.append(CursorHookInstaller.restartAfterRemoval)
        }
        return CursorHookInstallResult(outcome: outcome, printed: printed)
    }
}
