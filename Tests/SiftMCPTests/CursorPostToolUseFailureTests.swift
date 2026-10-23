//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import SiftMCP
import Testing

/// The Cursor half, through the built binary: Cursor's `Shell` results, a rewrite ticket and the diagnostics note.
@Suite(.temporaryDirectories)
struct CursorPostToolUseFailureTests {
    private static func located(_ scene: CursorPreToolUseTests.Scene) -> String {
        "\(CanonicalPath.of(scene.repo.path))/Sources/App/Depot.swift:2:9: error: cannot convert value"
    }

    private func result(_ scene: CursorPreToolUseTests.Scene, event: String, text: String, cwd: String = "") -> [String: Any] {
        var payload = CursorRewriteNoticeTests.post(scene)
        payload["hook_event_name"] = event
        payload["cwd"] = cwd
        if event == "postToolUseFailure" {
            payload["tool_output"] = nil
            payload["error_message"] = text
            payload["failure_type"] = "error"
            payload["is_interrupt"] = false
        } else {
            payload["tool_output"] = String(bytes: (try? JSONSerialization.data(withJSONObject: ["output": text, "exitCode": 0])) ?? Data(), encoding: .utf8)
        }
        return payload
    }

    private func context(_ printed: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        try #require(CursorPreToolUseTests.object(printed)["additional_context"] as? String, "printed \(printed)", sourceLocation: sourceLocation)
    }

    @Test func aFailedRewrittenBuildStillDeliversTheNoticeAndConsumesTheTicket() throws {
        let scene = try CursorPreToolUseTests.Scene()
        _ = try scene.run(scene.cursor("Shell", CursorBuildRewriteTests.build))
        let payload = result(scene, event: "postToolUseFailure", text: "exit 1")

        let first = try CursorRewriteNoticeTests.runPost(payload, in: scene)
        let second = try CursorRewriteNoticeTests.runPost(payload, in: scene)

        #expect(try context(first.printed).contains("the hook rewrote this to"))
        #expect(second.printed.isEmpty, "printed \(second.printed)")
    }

    @Test func aShellResultsOutputIsLocatedWithWorkspaceRootStandingInForAnEmptyCwd() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let payload = result(scene, event: "postToolUse", text: Self.located(scene))

        let run = try CursorRewriteNoticeTests.runPost(payload, in: scene)

        let note = try context(run.printed)

        #expect(note.contains("the diagnostics above, located"), "\(note)")
        #expect(note.contains("Sources/App/Depot.swift:2"), "\(note)")
    }

    @Test func aFailedShellCallsErrorMessageIsLocated() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let payload = result(scene, event: "postToolUseFailure", text: Self.located(scene), cwd: scene.repo.path)

        let run = try CursorRewriteNoticeTests.runPost(payload, in: scene)

        #expect(try context(run.printed).contains("the diagnostics above, located"), "\(run.printed)")
    }

    @Test func theNoticeAndTheNoteShareOneAnswerNoticeFirst() throws {
        let scene = try CursorPreToolUseTests.Scene()
        _ = try scene.run(scene.cursor("Shell", CursorBuildRewriteTests.build))
        let payload = result(scene, event: "postToolUse", text: Self.located(scene))

        let run = try CursorRewriteNoticeTests.runPost(payload, in: scene)

        let lines = try context(run.printed).split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.first?.contains("the hook rewrote this to") == true, "\(run.printed)")
        #expect(run.printed.components(separatedBy: "additional_context").count == 2, "\(run.printed)")
        #expect(try context(run.printed).contains("the diagnostics above, located"))
    }
}
