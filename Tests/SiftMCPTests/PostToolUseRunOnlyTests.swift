//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import Testing

/// Covers `post-tool-use --run-only`, which Cursor's and Codex's run mode register: their registrations cannot match on the tool, so the hook itself answers a shell call's result alone, as Claude Code's `Bash` matcher does in run mode.
@Suite(.temporaryDirectories)
struct PostToolUseRunOnlyTests {
    typealias Scene = CursorPostToolUseTests.Scene

    /// A write that leaves a Swift file unparseable draws nothing from the run-only hook and an answer from the plain one, in each harness's protocol.
    ///
    /// The run-only call goes first: the plain hook answers a content once, so after it the run-only hook would be silent whether or not it judged the write.
    @Test(arguments: Write.allCases)
    func aWriteTheFullHookAnswersDrawsNothing(write: Write) async throws {
        let scene = try await Scene()
        try Scene.broken.write(toFile: scene.catalogue, atomically: true, encoding: .utf8)
        let payload = write.payload(scene)

        let runOnly = try scene.run(stdin: JSONSerialization.data(withJSONObject: payload), agent: write.agent, flags: ["--run-only"])
        let full = try scene.run(payload, agent: write.agent)

        #expect(runOnly.status == 0)
        #expect(runOnly.printed.isEmpty, "\(runOnly.printed)")
        #expect(!full.printed.isEmpty)
    }

    /// A shell call is the one call run mode lets through, under each harness's name for it.
    @Test func onlyAShellCallIsLetThrough() {
        let bash: [String: Any] = ["hook_event_name": "PostToolUse", "tool_name": "Bash"]
        let write: [String: Any] = ["hook_event_name": "PostToolUse", "tool_name": "Write"]
        let patch: [String: Any] = ["hook_event_name": "PostToolUse", "tool_name": "apply_patch"]
        let shell: [String: Any] = ["hook_event_name": "postToolUse", "tool_name": "Shell"]
        let failedShell: [String: Any] = ["hook_event_name": "postToolUseFailure", "tool_name": "Shell"]
        let cursorWrite: [String: Any] = ["hook_event_name": "postToolUse", "tool_name": "Write"]

        #expect(PostToolUseCommand.isShellCall(bash, agent: .claude))
        #expect(!PostToolUseCommand.isShellCall(write, agent: .claude))
        #expect(!PostToolUseCommand.isShellCall(patch, agent: .claude))
        #expect(PostToolUseCommand.isShellCall(shell, agent: .cursor))
        #expect(PostToolUseCommand.isShellCall(failedShell, agent: .cursor))
        #expect(!PostToolUseCommand.isShellCall(cursorWrite, agent: .cursor))
        #expect(!PostToolUseCommand.isShellCall(bash, agent: .cursor))
    }
}

extension PostToolUseRunOnlyTests {
    /// A write of the broken catalogue as each harness reports it.
    enum Write: String, CaseIterable {
        case claude
        case codex
        case cursor

        var agent: String? {
            self == .cursor ? "cursor" : nil
        }

        func payload(_ scene: Scene) -> [String: Any] {
            switch self {
            case .claude:
                scene.claude(scene.catalogue, content: Scene.broken)
            case .codex:
                CodexPostToolUseTests.codex(Self.update(scene), in: scene)
            case .cursor:
                scene.cursor(scene.catalogue, content: Scene.broken)
            }
        }

        /// An `apply_patch` section replacing the catalogue with the broken source.
        private static func update(_ scene: Scene) -> String {
            let path = (scene.catalogue as NSString).lastPathComponent
            return CodexPostToolUseTests.add(path, Scene.broken)
        }
    }
}
