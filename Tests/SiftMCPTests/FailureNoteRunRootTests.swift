//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
import SiftMCP
import Testing

/// A failed `swift-sure run` is located in the tree it ran against, named by its `--root` or a leading `cd`, and not in the tree the hook payload's `cwd` is in.
@Suite(.temporaryDirectories)
struct FailureNoteRunRootTests {
    private static var path: String {
        "Sources/Gizmo/Widget.swift"
    }

    /// A source whose line 3 sits inside a function named `name`.
    private static func source(function name: String) -> String {
        "struct Widget {\n    func \(name)() {\n        let x = 1 + \"a\"\n    }\n}\n"
    }

    private static func payload(command: String, cwd: String) -> [String: Any] {
        [
            "hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": ["command": command],
            "tool_use_id": "t1", "session_id": "s1", "cwd": cwd, "is_interrupt": false,
            "error": "Exit code 1\n\(path):3:19: error: binary operator '+' cannot be applied",
        ]
    }

    /// Two repositories holding the same path with different declarations at line 3; `second` omits the file when `present` is false.
    private func answer(second present: Bool = true, _ command: (_ first: String, _ second: String) -> String) throws -> String {
        let first = try MCPTestRepo.make(declaring: "Depot")
        let second = try MCPTestRepo.make(declaring: "Depot")
        try MCPTestRepo.add([Self.path: Self.source(function: "restock")], to: first)
        if present {
            try MCPTestRepo.add([Self.path: Self.source(function: "reorder")], to: second)
        }
        let recorded = RecordedOutput()
        PostToolUseCommand.answerFailure(to: Self.payload(command: command(first.path, second.path), cwd: first.path), output: recorded.output)
        return recorded.printed
    }

    @Test func aRootOptionNamesTheTreeTheDiagnosticIsLocatedIn() throws {
        let printed = try answer { _, second in "swift-sure run --root \(second) -- swift test" }

        #expect(printed.contains("reorder"))
        #expect(!printed.contains("restock"))
    }

    @Test func aLeadingChangeOfDirectoryNamesTheTree() throws {
        let printed = try answer { _, second in "(cd \(second) && swift-sure run -- swift build)" }

        #expect(printed.contains("reorder"))
        #expect(!printed.contains("restock"))
    }

    @Test func aRunWithoutEitherIsLocatedFromTheCallersDirectory() throws {
        let printed = try answer { _, _ in "swift-sure run -- swift build" }

        #expect(printed.contains("restock"))
    }

    @Test func aFileMissingUnderTheRunsRootGetsNoNoteFromAnotherTree() throws {
        let printed = try answer(second: false) { _, second in "swift-sure run --root \(second) -- swift test" }

        #expect(printed.isEmpty)
    }
}
