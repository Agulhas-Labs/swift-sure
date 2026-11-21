//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// The branches of the hook's piped-run trim that decide whether the amendment goes out, through the built hook: a tree with no Swift, Cursor's permission rules in both directions, and run-only mode under Claude Code's permission modes.
@Suite(.temporaryDirectories)
struct PipedRunTrimHookBranchTests {
    private static var piped: String {
        "swift build 2>&1 | grep error"
    }

    /// Under Cursor, where an allow rule covers the wrapping, the trim goes out as an amendment.
    @Test
    func cursorAmendsWhereTheWrappingIsAllowed() throws {
        let scene = try CursorPreToolUseTests.Scene()
        try CursorBuildRewriteTests.write(#"{"permissions": {"allow": ["Shell(swift-sure)"]}}"#, in: scene.repo)
        let run = try scene.run(scene.cursor("Shell", ["command": "swift test 2>&1 | tail -40", "cwd": "", "timeout": 30000]))
        let input = try #require(CursorPreToolUseTests.object(run.printed)["updated_input"] as? [String: Any])

        #expect(input["command"] as? String == "swift-sure run -- swift test")
    }

    /// Under Cursor, where the line as written is allowed stage by stage and the wrapping is not, the trim would add a prompt, so the line runs as written.
    @Test
    func cursorLeavesTheLineWhereTrimmingWouldAddAPrompt() throws {
        let scene = try CursorPreToolUseTests.Scene()
        try CursorBuildRewriteTests.write(#"{"permissions": {"allow": ["Shell(swift)", "Shell(tail)"]}}"#, in: scene.repo)
        let run = try scene.run(scene.cursor("Shell", ["command": "swift test 2>&1 | tail -40", "cwd": "", "timeout": 30000]))

        #expect(run.status == 0)
        #expect(!run.printed.contains("updated_input"), "printed \(run.printed)")
    }

    /// A raw build piped into a trimmer, in a tree holding no Swift file, is not wrapped: the line is read as before.
    @Test
    func aTreeWithNoSwiftIsNotAmended() throws {
        let empty = try TemporaryDirectory.make("piped-trim-empty")
        let home = try TemporaryDirectory.make("piped-trim-home")
        let printed = try PipedRunTrimTests.run(["pre-tool-use"], command: Self.piped, in: empty, home: home)
        let probed = try PipedRunTrimTests.run(["pre-tool-use", "--verdict"], command: Self.piped, in: empty, home: home)

        #expect(!printed.contains("updatedInput"), "\(printed)")
        #expect(!probed.contains("trimmed"), "\(probed)")

        let root = try PipedRunTrimTests.package()
        let control = try PipedRunTrimTests.run(["pre-tool-use", "--verdict"], command: Self.piped, in: root, home: home)
        #expect(control.hasSuffix("trimmed\n") || control.contains("\ttrimmed"), "\(control)")
    }

    /// Under `--run-only` in a mode that asks, the trim is made only where an allow rule covers the wrapping.
    @Test
    func runOnlyInAnAskingModeAmendsOnlyWithAnAllowRule() throws {
        let root = try PipedRunTrimTests.package()
        let bare = try PipedRunTrimTests.home(allowing: [])
        let denied = try PipedRunTrimTests.run(["pre-tool-use", "--run-only", "--verdict"], command: Self.piped, in: root, home: bare, mode: "default")
        let printed = try PipedRunTrimTests.run(["pre-tool-use", "--run-only"], command: Self.piped, in: root, home: bare, mode: "default")

        #expect(!denied.contains("trimmed"), "\(denied)")
        #expect(!printed.contains("updatedInput"), "\(printed)")

        let allowed = try PipedRunTrimTests.home(allowing: ["Bash(swift-sure run:*)"])
        let amended = try PipedRunTrimTests.run(["pre-tool-use", "--run-only", "--verdict"], command: Self.piped, in: root, home: allowed, mode: "default")
        #expect(amended.hasPrefix("amended\t") && amended.contains("\ttrimmed"), "\(amended)")
    }
}
