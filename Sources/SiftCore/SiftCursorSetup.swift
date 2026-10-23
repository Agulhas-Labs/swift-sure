//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// What SwiftSure registers with Cursor, as values for the shared Fieldwork library: the `mcp.json` server, the `hooks.json` hooks, the install over both and what its output says is not carried over.
///
/// The library does the registering; this is the one place that says what SwiftSure registers in Cursor, beside ``SiftClaudeSetup``.
public struct SiftCursorSetup {
    /// What the install output names as not carried over to Cursor, one line each.
    public static let unsupported = [
        "unsupported on Cursor: \(ProductName.current.binary) audit — Cursor's transcript format is not a documented interface",
        "unsupported on Cursor: the subagent primer — no Cursor hook for a subagent's start has been verified",
        "unsupported on Cursor: a machine-wide Swift rule — Cursor's rules are per project",
    ]

    /// Said on every install, since nothing yet shows the whole path working in a live Cursor.
    public static var experimental: String {
        "experimental: Cursor support has not yet been verified end to end in a live Cursor"
    }

    /// The server in the Cursor directory's `mcp.json`: the same server Claude Code gets.
    public static let mcp = CursorMcpFile(server: SiftClaudeSetup.server)

    /// Every event SwiftSure registers for in `hooks.json` and the subcommand each one runs, in the order an answer lists them.
    public static let hooks = CursorHooksFile(
        tool: .sift,
        agentFlag: "--agent cursor",
        hooks: [
            CursorHooksFile.Hook(event: "sessionStart", subcommand: SiftClaudeSetup.sessionStartSubcommand),
            CursorHooksFile.Hook(event: "preToolUse", subcommand: SiftClaudeSetup.preToolUseSubcommand),
            CursorHooksFile.Hook(event: "postToolUse", subcommand: "post-tool-use"),
            CursorHooksFile.Hook(event: "postToolUseFailure", subcommand: "post-tool-use"),
        ]
    )

    /// The install over both files.
    public static let install = CursorInstall(mcp: mcp, hooks: hooks, directoryFlag: "--cursor-dir")

    /// The install with what it says around the merge.
    public static let installer = CursorHookInstaller(cursor: install, unsupported: unsupported, experimental: experimental)

    /// The Cursor install as each name the build answers to registers it, current first, so a hook or server an earlier release left in Cursor's directory is found.
    public static var recognisedInstalls: [CursorInstall] {
        ProductName.recognised.map { name in
            CursorInstall(
                mcp: CursorMcpFile(server: SiftClaudeSetup.server(named: name)),
                hooks: CursorHooksFile(tool: SiftClaudeSetup.hooks(named: name).tool, agentFlag: hooks.agentFlag, hooks: hooks.hooks),
                directoryFlag: install.directoryFlag
            )
        }
    }

    /// The Cursor step of `swift-sure install`.
    public static let step = CursorInstallStep(installer: installer)

    /// The bytes at `url` in the Cursor directory, `nil` when nothing is there; a file that cannot be read, or a link that leads nowhere, is refused.
    public static func read(_ url: URL) throws -> Data? {
        try SettingsFile.read(url, agent: "cursor", flag: install.directoryFlag)
    }

    /// Whether `data`, a Cursor `hooks.json`, holds a hook of SwiftSure's for any event SwiftSure registers.
    public static func registersAHook(in data: Data?) -> Bool {
        let file = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let events = file?["hooks"] as? [String: Any] ?? [:]
        return hooks.hooks.contains { hook in
            let entries = events[hook.event] as? [[String: Any]] ?? []
            return entries.compactMap { $0["command"] as? String }.contains { command in FieldworkTool.recognised.contains { $0.runs(command, subcommand: hooks.registeredSubcommand(for: hook)) } }
        }
    }
}
