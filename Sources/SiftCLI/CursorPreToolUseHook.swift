//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftMCP

/// `pre-tool-use --agent cursor`: the shared translation of Cursor's `preToolUse` payload and answer, with the tool-name mapping of SwiftSure's own MCP server supplied and the rewrite notice filed for the call's `postToolUse`.
struct CursorPreToolUseHook {
    /// The Claude Code payload `payload` stands for, or `nil` where it is not a `preToolUse` payload of a tool input this reads; a call to SwiftSure's MCP server goes by the name Claude Code gives it.
    static func claudePayload(from payload: [String: Any]) -> [String: Any]? {
        CursorPreToolUse.claudePayload(from: payload) { name, input in
            IndexToolName.tool(namedByCursor: name, input: input).map { IndexToolName.prefix + $0 }
        }
    }

    /// What Cursor is told for the hook's Claude Code `output`, or `nil` where its schema has no room for it.
    static func response(to output: String, toolName: String?) -> String? {
        CursorPreToolUse.response(to: output, toolName: toolName) { IndexToolName.tool(named: $0) != nil }
    }

    /// Files the hook's rewrite notice for the call's `postToolUse`, where `response` amends a Shell input and `output` carried context for the model.
    static func fileNotice(output: String, response: String, payload: [String: Any], notices: CursorRewriteNotices = .standard()) {
        guard let ticket = CursorPreToolUse.ticket(output: output, response: response, claudePayload: payload) else { return }
        notices.file(ticket.notice, session: ticket.session, call: ticket.call)
    }
}
