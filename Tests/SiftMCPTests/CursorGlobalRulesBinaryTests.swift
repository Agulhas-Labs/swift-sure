//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// Cursor's global rules file, read by the built `swift-sure pre-tool-use` from the home it runs under rather than only by the reader.
@Suite(.temporaryDirectories)
struct CursorGlobalRulesBinaryTests {
    /// A deny rule in the global `cli-config.json` that names the build keeps the hook from rewriting it: nothing is printed.
    @Test
    func aGlobalDenyRuleMakesTheBinaryStandAside() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let directory = scene.home.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"permissions": {"deny": ["Shell(swift)"]}}"#.write(to: directory.appendingPathComponent("cli-config.json"), atomically: true, encoding: .utf8)
        let run = try CursorHookProcess.run(["pre-tool-use", "--agent", "cursor"], payload: scene.cursor("Shell", CursorBuildRewriteTests.build), in: scene)

        #expect(run.status == 0)
        #expect(run.printed.isEmpty, "printed \(run.printed)")
    }

    /// With no global file the same build is rewritten, so the stand-aside above is the rule's doing.
    @Test
    func withoutAGlobalFileTheBinaryRewrites() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let run = try CursorHookProcess.run(["pre-tool-use", "--agent", "cursor"], payload: scene.cursor("Shell", CursorBuildRewriteTests.build), in: scene)

        #expect(run.printed.contains("updated_input"), "printed \(run.printed)")
    }
}
