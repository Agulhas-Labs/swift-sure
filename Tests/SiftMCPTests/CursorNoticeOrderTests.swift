//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import Testing

/// The order the `preToolUse` hook files a Cursor rewrite's notice and prints its response in.
struct CursorNoticeOrderTests {
    /// The notice is filed before the response is printed, so a `postToolUse` that fires as soon as Cursor reads stdout finds it.
    @Test
    func theNoticeIsFiledBeforeTheResponseIsPrinted() {
        let output = #"{"hookSpecificOutput":{"updatedInput":{"command":"swift-sure run -- swift test"},"additionalContext":"rewritten"}}"#
        var events: [String] = []

        PreToolUseCommand.deliver(
            output,
            payload: ["tool_name": "Bash", "session_id": "s", "tool_use_id": "t1"],
            agent: .cursor,
            emit: { _ in events.append("print") },
            file: { _, _ in events.append("file") }
        )

        #expect(events == ["file", "print"], "events \(events)")
    }
}
