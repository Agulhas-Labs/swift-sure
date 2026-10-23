//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// A two-statement build line through Cursor's prompt rule, driven through the built binary: rewritten as a whole unless an allow rule covers each statement as written and not the wrapping.
@Suite(.temporaryDirectories)
struct CursorMultiLegRewriteTests {
    /// Where an allow rule covers both builds as written but not the wrapping, the rewrite would add a prompt and the line runs as written; where it covers only one build, Cursor would prompt about the line anyway and every statement is wrapped.
    @Test(arguments: [
        (#"{"permissions": {"allow": ["Shell(swift)"]}}"#, false),
        (#"{"permissions": {"allow": ["Shell(swift:build)"]}}"#, true),
    ])
    func aMultiLegLineIsRewrittenUnlessTheRewriteAddsAPrompt(rules: String, rewritten: Bool) throws {
        let scene = try CursorPreToolUseTests.Scene()
        try CursorBuildRewriteTests.write(rules, in: scene.repo)
        let input: [String: Any] = ["command": "swift build && swift test", "cwd": "", "timeout": 30000]
        let run = try CursorHookProcess.run(["pre-tool-use", "--agent", "cursor"], payload: scene.cursor("Shell", input), in: scene)

        #expect(run.status == 0)
        if rewritten {
            let amended = try #require(CursorPreToolUseTests.object(run.printed)["updated_input"] as? [String: Any], "printed \(run.printed)")
            #expect(amended["command"] as? String == "swift-sure run -- swift build && swift-sure run -- swift test")
        } else {
            #expect(run.printed.isEmpty, "printed \(run.printed)")
        }
    }
}
