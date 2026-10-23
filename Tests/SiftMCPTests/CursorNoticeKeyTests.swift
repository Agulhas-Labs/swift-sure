//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// What a rewrite ticket is keyed by, through the built binary: the session and the call, the session being the payload's session id or else its conversation id.
@Suite(.temporaryDirectories)
struct CursorNoticeKeyTests {
    /// The same call id in another session finds no ticket.
    @Test
    func theSameCallInAnotherSessionGetsNothing() throws {
        let scene = try CursorPreToolUseTests.Scene()
        _ = try scene.run(scene.cursor("Shell", CursorBuildRewriteTests.build))
        let other = try CursorHookProcess.run(["post-tool-use", "--agent", "cursor"], payload: CursorHookProcess.post(in: scene, session: "another-session"), in: scene)
        let own = try CursorHookProcess.run(["post-tool-use", "--agent", "cursor"], payload: CursorHookProcess.post(in: scene, session: "cursor-session"), in: scene)

        #expect(other.printed.isEmpty, "printed \(other.printed)")
        #expect(own.printed.contains("the hook rewrote this to"), "printed \(own.printed)")
    }

    /// With no session id in either payload, the conversation id stands in for it, so the ticket is filed and found.
    @Test
    func theConversationIdStandsInForAMissingSessionId() throws {
        let scene = try CursorPreToolUseTests.Scene()
        var pre = scene.cursor("Shell", CursorBuildRewriteTests.build)
        pre["session_id"] = nil
        let filed = try scene.run(pre)
        let post = try CursorHookProcess.run(["post-tool-use", "--agent", "cursor"], payload: CursorHookProcess.post(in: scene, session: nil), in: scene)

        #expect(filed.printed.contains("updated_input"), "printed \(filed.printed)")
        #expect(post.printed.contains("the hook rewrote this to"), "printed \(post.printed)")
    }
}
