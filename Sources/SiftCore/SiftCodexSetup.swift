//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// What SwiftSure registers with Codex, as values for the shared Fieldwork library: the MCP server registered through `codex mcp` and the hooks in the Codex home's `hooks.json`.
///
/// The library does the looking up and the checking; this is the one place that says what SwiftSure registers in Codex, beside ``SiftClaudeSetup`` and ``SiftCursorSetup``.
public struct SiftCodexSetup {
    /// The server registered through `codex mcp`: the same server Claude Code gets.
    public static let server = CodexMcpServer(server: SiftClaudeSetup.server)

    /// The subcommand run mode's `PostToolUse` handler runs: it answers a shell call's result alone, since Codex's registration cannot narrow on the tool.
    public static var runPostToolUseSubcommand: String {
        "post-tool-use --run-only"
    }

    /// The hooks SwiftSure registers in Codex's `hooks.json`: the session start and the shell and edit hooks.
    public static let hooksFile = CodexHooksFile(
        tool: .sift,
        hooks: [
            CodexHooksFile.Hook(event: "SessionStart", subcommand: SiftClaudeSetup.sessionStartSubcommand, matcher: nil),
            CodexHooksFile.Hook(event: "PreToolUse", subcommand: SiftClaudeSetup.preToolUseSubcommand, matcher: "*"),
            CodexHooksFile.Hook(event: "PostToolUse", subcommand: "post-tool-use", matcher: "*"),
        ]
    )

    /// The hooks run mode registers in `hooks.json`: the shell hooks alone, with no session start, each running its subcommand with the run-only flag.
    public static let runHooksFile = CodexHooksFile(
        tool: .sift,
        hooks: [
            CodexHooksFile.Hook(event: "PreToolUse", subcommand: SiftClaudeSetup.runOnlyPreToolUseSubcommand, matcher: "*"),
            CodexHooksFile.Hook(event: "PostToolUse", subcommand: runPostToolUseSubcommand, matcher: "*"),
        ]
    )

    /// The hooks file of `mode`.
    public static func hooksFile(of mode: SiftClaudeSetup.InstallMode) -> CodexHooksFile {
        mode == .index ? hooksFile : runHooksFile
    }

    /// Whether the `hooks.json` bytes `data` hold both modes' `PreToolUse` handler of ours: the run-mode one and the full set's.
    public static func registersBothModes(_ data: Data?) -> Bool {
        guard mode(of: data) == .run, let hook = hooksFile.hooks.first(where: { $0.event == "PreToolUse" }) else { return false }
        return !hooksFile.commands(in: data, for: hook).isEmpty
    }

    /// The hooks SwiftSure registers in Codex, one event each, as the doctor reads them.
    public static let hooks = HookRegistration(tool: .sift, events: registrationEvents(of: hooksFile))

    /// The hooks run mode registers in Codex: the shell hooks alone, as the doctor reads them.
    public static let runHooks = HookRegistration(tool: .sift, events: registrationEvents(of: runHooksFile))

    /// What the install output names as not carried over to Codex, one line each.
    public static let unsupported = [
        "unsupported on Codex: \(ProductName.current.binary) audit — Codex's session log is not a documented interface",
        "unsupported on Codex: a Swift-scoped rule — Codex's AGENTS.md applies to every project, so none is written",
        "unsupported on Codex: the subagent primer — no Codex hook for a subagent's start has been verified",
        "unsupported on Codex: the post-edit note for a file apply_patch moves — no payload of a move has been captured",
    ]

    /// Said on every install, since nothing yet shows the whole path working in a live Codex.
    public static var experimental: String {
        "experimental: Codex support has not yet been verified end to end in a live Codex session"
    }

    /// The install of the index set alone, the hooks file and the server together, with no run mode and no legacy settling.
    ///
    /// Internal, so a caller installs only through the mode-aware install, which adds both.
    static let indexInstall = CodexInstall(hooks: hooksFile, server: server)

    /// The installer that prints the install and uninstall answers, internal for the same reason.
    static let installer = CodexHookInstaller(codex: indexInstall, unsupported: unsupported, experimental: experimental)

    /// The line asking for Codex to be restarted once an install has changed something.
    public static var restart: String {
        installer.restart
    }

    private static func registrationEvents(of file: CodexHooksFile) -> [HookRegistration.Event] {
        file.hooks.map { hook in
            HookRegistration.Event(name: hook.event, subcommand: hook.subcommand, matchers: hook.matcher.map { [$0] } ?? [], timeout: 5)
        }
    }
}
