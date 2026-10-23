//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A transcript recorded under a plugin's tool names reads as the bare names do, in the scan and in the audit.
@Suite(.temporaryDirectories)
struct PluginToolNameTranscriptTests {
    private static var plugin: String {
        "mcp__plugin_\(ProductName.current.word)_\(ProductName.current.word)__"
    }

    @Test func aPluginFormDigestIsAnIndexLookupInTheScan() {
        let lookups = TranscriptFixture.lookups([
            TranscriptFixture.toolUse(Self.plugin + "digest", id: "d1", input: ["target": "Gizmo"]),
            TranscriptFixture.indexAnswer(id: "d1", text: "tree: App  head: 0000000  dirty: 0  parse_errors: 0\nGizmo — App — Gizmo.swift:2-40"),
        ])

        #expect(lookups == [.indexed])
    }

    @Test func aNearMissNameIsNoLookupInTheScan() {
        let word = ProductName.current.word
        let lookups = TranscriptFixture.lookups([
            TranscriptFixture.toolUse("mcp__plugin_x_\(word)x__digest", id: "d1", input: ["target": "Gizmo"]),
            TranscriptFixture.toolUse("mcp__\(word)ly__digest", id: "d2", input: ["target": "Gizmo"]),
        ])

        #expect(lookups.isEmpty)
    }

    @Test func aPluginFormCallIsAnAnswerInTheAuditVerbs() throws {
        let directory = try TemporaryDirectory.make("plugin-verbs")
        let call: [String: Any] = [
            "type": "assistant",
            "message": ["id": "m1", "usage": ["input_tokens": 1], "content": [["type": "tool_use", "id": "a", "name": Self.plugin + "where", "input": ["symbol": "Gizmo"]]]],
        ]
        let end: [String: Any] = ["type": "assistant", "message": ["id": "m2", "usage": ["input_tokens": 1], "content": [["type": "text", "text": "done"]]]]
        let lines = try [
            JSONSerialization.data(withJSONObject: call),
            TranscriptFixture.indexAnswer(id: "a", text: "one"),
            JSONSerialization.data(withJSONObject: end),
        ]
        let file = directory.appendingPathComponent("projects/-repo/session.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.flatMap { $0 + [0x0A] }).write(to: file)
        let snapshot = TranscriptSnapshot.take(projectsDirectory: directory.appendingPathComponent("projects"), since: nil, transcript: nil)
        let report = AuditVerbs.report(snapshot: snapshot, since: nil, until: nil, window: "--since 7d")

        #expect(report.hasPrefix("audit --verbs: 1 answer in 1 session"))
    }
}
