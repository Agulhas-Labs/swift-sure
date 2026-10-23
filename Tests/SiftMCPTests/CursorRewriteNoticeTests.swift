//
// Copyright © Agulhas Labs
//

import Foundation
import SiftMCP
import Testing

/// The notice that a Cursor build was rewritten in place: filed by the `preToolUse` hook, handed to the model by the same call's `postToolUse`, through the built binary.
@Suite(.temporaryDirectories)
struct CursorRewriteNoticeTests {
    /// The rewritten call's `postToolUse` prints the rewrite notice as context.
    @Test
    func theRewrittenCallsPostToolUseCarriesTheNotice() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let pre = try scene.run(scene.cursor("Shell", CursorBuildRewriteTests.build))
        #expect(pre.printed.contains("updated_input"), "printed \(pre.printed)")

        let post = try Self.runPost(Self.post(scene), in: scene)

        let context = try #require(CursorPreToolUseTests.object(post.printed)["additional_context"] as? String, "printed \(post.printed)")
        #expect(context.contains("the hook rewrote this to"))
        #expect(context.contains("swift test 2>&1 | cat"))
    }

    /// A ticket is taken once: the same `postToolUse` again prints nothing.
    @Test
    func aTicketIsTakenOnce() throws {
        let scene = try CursorPreToolUseTests.Scene()
        _ = try scene.run(scene.cursor("Shell", CursorBuildRewriteTests.build))
        let first = try Self.runPost(Self.post(scene), in: scene)
        let second = try Self.runPost(Self.post(scene), in: scene)

        #expect(!first.printed.isEmpty)
        #expect(second.printed.isEmpty, "printed \(second.printed)")
    }

    /// A `postToolUse` for another call prints nothing.
    @Test
    func anotherCallsPostToolUseIsSilent() throws {
        let scene = try CursorPreToolUseTests.Scene()
        _ = try scene.run(scene.cursor("Shell", CursorBuildRewriteTests.build))
        let post = try Self.runPost(Self.post(scene, call: "t2"), in: scene)

        #expect(post.printed.isEmpty, "printed \(post.printed)")
    }

    /// A build the hook lets through is not rewritten, so it files no ticket.
    @Test
    func aBuildLetThroughFilesNoTicket() throws {
        let scene = try CursorPreToolUseTests.Scene()
        try CursorBuildRewriteTests.write(#"{"permissions": {"deny": ["Shell(swift)"]}}"#, in: scene.repo)
        let pre = try scene.run(scene.cursor("Shell", CursorBuildRewriteTests.build))
        let post = try Self.runPost(Self.post(scene), in: scene)

        #expect(pre.printed.isEmpty, "printed \(pre.printed)")
        #expect(post.printed.isEmpty, "printed \(post.printed)")
    }

    /// Filing a ticket prunes those older than an hour, and keeps a fresh one.
    @Test
    func filingPrunesTicketsOlderThanAnHour() throws {
        let directory = try TemporaryDirectory.make("cursor-rewrites")
        let notices = CursorRewriteNotices(directory: directory)
        notices.file("stale", session: "s", call: "old")
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-61 * 60)], ofItemAtPath: directory.appendingPathComponent(name).path)
        }
        notices.file("fresh", session: "s", call: "new")

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
        #expect(notices.take(session: "s", call: "new") == "fresh")
        #expect(notices.take(session: "s", call: "old") == nil)
    }

    /// A build running longer than ten minutes still gets its notice when another rewrite is filed meanwhile.
    @Test
    func aTicketFifteenMinutesOldSurvivesALaterFiling() throws {
        let directory = try TemporaryDirectory.make("cursor-rewrites")
        let notices = CursorRewriteNotices(directory: directory)
        notices.file("long build", session: "s", call: "slow")
        try Self.age(directory, minutes: 15)
        notices.file("another", session: "s", call: "other")

        #expect(notices.take(session: "s", call: "slow") == "long build")
    }

    /// Reading a ticket deletes the orphans older than an hour, though nothing is filed.
    @Test
    func aReadPrunesAnHourOldOrphan() throws {
        let directory = try TemporaryDirectory.make("cursor-rewrites")
        let notices = CursorRewriteNotices(directory: directory)
        notices.file("orphan", session: "s", call: "orphan")
        try Self.age(directory, minutes: 61)

        #expect(notices.take(session: "s", call: "none") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

extension CursorRewriteNoticeTests {
    /// Backdates every ticket under `directory` by `minutes`.
    static func age(_ directory: URL, minutes: Double) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-minutes * 60)], ofItemAtPath: directory.appendingPathComponent(name).path)
        }
    }

    /// The Cursor `postToolUse` payload for the Shell call the scene's `preToolUse` rewrote, carrying the rewritten line.
    static func post(_ scene: CursorPreToolUseTests.Scene, call: String = "t1") -> [String: Any] {
        [
            "conversation_id": "c1", "generation_id": "g1", "model": "default", "tool_name": "Shell",
            "tool_input": ["command": "swift-sure run -- swift test", "cwd": "", "timeout": 30000],
            "tool_output": "{\"output\":\"ok\\n\",\"exitCode\":0}", "tool_use_id": call, "cwd": "", "session_id": "cursor-session",
            "hook_event_name": "postToolUse", "cursor_version": "1.0", "workspace_roots": [scene.repo.path],
        ]
    }

    /// Runs this build's `swift-sure post-tool-use --agent cursor` on `payload`, with the scene's advice directory.
    static func runPost(_ payload: [String: Any], in scene: CursorPreToolUseTests.Scene, sourceLocation: SourceLocation = #_sourceLocation) throws -> (status: Int32, printed: String) {
        let binary = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle", sourceLocation: sourceLocation)
        let process = Process()
        process.executableURL = binary
        process.arguments = ["post-tool-use", "--agent", "cursor"]
        process.currentDirectoryURL = scene.repo
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["CFFIXED_USER_HOME"] = scene.home.path
        environment["SWIFT_SURE_HOME"] = scene.home.appendingPathComponent("swift-sure").path
        environment["SWIFT_SURE_ADVICE_DIR"] = scene.home.appendingPathComponent("advice").path
        environment["SWIFT_SURE_USAGE_LOG"] = scene.home.appendingPathComponent("usage.jsonl").path
        environment["SWIFT_SURE_NO_ADVICE"] = nil
        environment["CLAUDE_CONFIG_DIR"] = scene.home.appendingPathComponent("claude").path
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: payload))
        input.fileHandleForWriting.closeFile()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: printed, encoding: .utf8) ?? "")
    }
}
