//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftMCP

/// `post-tool-use --agent cursor`: what the hook prints for Claude Code, written back in Cursor's schema, and the rewrite notice the `preToolUse` hook filed for the call.
struct CursorPostToolUseHook {
    /// The standard streams, carrying only what ``CursorPostToolUse/response(to:)`` makes of each line the hook would print for Claude Code.
    static let output = CommandOutput(
        keepsPartMarker: true,
        emit: { line in
            if let response = CursorPostToolUse.response(to: line) {
                StandardStreams.emit(response)
            }
        },
        emitRaw: { _ in },
        emitError: { StandardStreams.emitError($0) }
    )

    /// The notice that the `preToolUse` hook rewrote this `Shell` call, taken from the ticket it filed for the call, or `nil` where there is none.
    static func rewriteNotice(for payload: [String: Any], notices: CursorRewriteNotices = .standard()) -> String? {
        CursorPostToolUse.rewriteNotice(for: payload, take: notices.take(session:call:))
    }
}
