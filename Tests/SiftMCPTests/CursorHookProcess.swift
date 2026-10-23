//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// Runs the built `swift-sure` hooks as a Cursor session would, with every path the hook writes or reads under the scene's own temporary directories and `HOME` pointed at the scene's home.
struct CursorHookProcess {
    /// The advice directory a scene's hooks use.
    static func adviceDirectory(_ scene: CursorPreToolUseTests.Scene) -> URL {
        scene.home.appendingPathComponent("advice")
    }

    /// The directory the rewrite tickets are filed in.
    static func tickets(_ scene: CursorPreToolUseTests.Scene) -> URL {
        adviceDirectory(scene).appendingPathComponent("cursor-rewrites")
    }

    /// Runs `swift-sure` with `arguments` on `payload`, in the scene's repository: its exit status and what it printed.
    static func run(
        _ arguments: [String],
        payload: [String: Any],
        in scene: CursorPreToolUseTests.Scene,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (status: Int32, printed: String) {
        let binary = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle", sourceLocation: sourceLocation)
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = scene.repo
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["HOME"] = scene.home.path
        environment["CFFIXED_USER_HOME"] = scene.home.path
        environment["SWIFT_SURE_HOME"] = scene.home.appendingPathComponent("swift-sure").path
        environment["SWIFT_SURE_SERVER_LOG"] = scene.home.appendingPathComponent("server.jsonl").path
        environment["SWIFT_SURE_ADVICE_DIR"] = adviceDirectory(scene).path
        environment["SWIFT_SURE_USAGE_LOG"] = scene.home.appendingPathComponent("usage.jsonl").path
        environment["SWIFT_SURE_NO_ADVICE"] = nil
        environment["CLAUDE_CODE_SESSION_ID"] = nil
        environment["CLAUDE_CONFIG_DIR"] = scene.home.appendingPathComponent("claude").path
        environment["CLAUDE_PROJECT_DIR"] = nil
        environment["SWIFT_SURE_TEST_INPLACE_BUDGET"] = "60"
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

    /// The Cursor `postToolUse` payload for the call `call` of a `swift test` rewritten in place, carrying `session` as its session id where one is given and none where not.
    static func post(in scene: CursorPreToolUseTests.Scene, call: String = "t1", session: String?) -> [String: Any] {
        var payload = CursorRewriteNoticeTests.post(scene, call: call)
        payload["session_id"] = session
        return payload
    }
}
