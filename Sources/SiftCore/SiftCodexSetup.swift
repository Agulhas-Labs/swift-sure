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

    /// The hooks SwiftSure registers in Codex, one event each, as the doctor reads them.
    public static let hooks = HookRegistration(
        tool: .sift,
        events: CodexHooksFile.hooks.map { hook in
            HookRegistration.Event(name: hook.event, subcommand: hook.subcommand, matchers: hook.matcher.map { [$0] } ?? [], timeout: 5)
        }
    )
}
