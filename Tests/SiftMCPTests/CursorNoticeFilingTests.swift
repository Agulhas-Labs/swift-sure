//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// When the Cursor rewrite files no ticket, or cannot, through the built binary.
@Suite(.temporaryDirectories)
struct CursorNoticeFilingTests {
    /// A probe with `--verdict` prints a verdict line and files nothing.
    @Test
    func aVerdictProbeFilesNothing() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let run = try CursorHookProcess.run(["pre-tool-use", "--agent", "cursor", "--verdict"], payload: scene.cursor("Shell", CursorBuildRewriteTests.build), in: scene)
        let post = try CursorHookProcess.run(["post-tool-use", "--agent", "cursor"], payload: CursorHookProcess.post(in: scene, session: "cursor-session"), in: scene)

        #expect(run.printed.hasPrefix("amended"), "printed \(run.printed)")
        #expect(!FileManager.default.fileExists(atPath: CursorHookProcess.tickets(scene).path))
        #expect(post.printed.isEmpty, "printed \(post.printed)")
    }

    /// A build rewritten in place under Claude Code, which carries its notice itself, files no ticket.
    @Test
    func theClaudeCodePathFilesNothing() throws {
        let scene = try CursorPreToolUseTests.Scene()
        var payload = scene.claude("Bash", ["command": "swift test"])
        payload["permission_mode"] = "bypassPermissions"
        let run = try CursorHookProcess.run(["pre-tool-use"], payload: payload, in: scene)

        #expect(run.status == 0)
        #expect(run.printed.contains("updatedInput") && run.printed.contains("additionalContext"), "printed \(run.printed)")
        #expect(!FileManager.default.fileExists(atPath: CursorHookProcess.tickets(scene).path))
    }

    /// Where the tickets cannot be written, the rewrite is still answered, the hook exits cleanly, and the call's `postToolUse` delivers nothing.
    @Test
    func anUnwritableAdviceDirectoryStillAnswersAndDeliversNothing() throws {
        let scene = try CursorPreToolUseTests.Scene()
        try FileManager.default.createDirectory(at: CursorHookProcess.adviceDirectory(scene), withIntermediateDirectories: true)
        try "in the way".write(to: CursorHookProcess.tickets(scene), atomically: true, encoding: .utf8)
        let run = try CursorHookProcess.run(["pre-tool-use", "--agent", "cursor"], payload: scene.cursor("Shell", CursorBuildRewriteTests.build), in: scene)
        let post = try CursorHookProcess.run(["post-tool-use", "--agent", "cursor"], payload: CursorHookProcess.post(in: scene, session: "cursor-session"), in: scene)

        #expect(run.status == 0)
        #expect(run.printed.contains("updated_input"), "printed \(run.printed)")
        #expect(post.status == 0)
        #expect(post.printed.isEmpty, "printed \(post.printed)")
    }
}
