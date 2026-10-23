//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Every reader of a recorded call accepts each name the build answers to, not only the current one, so a transcript written before a rename still parses.
@Suite(.temporaryDirectories)
struct RecognisedNameParserTests {
    private static let current = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let legacy = ProductName.current
    private static var both: [ProductName] {
        [current, legacy]
    }

    @Test func theBinaryPrefixIsRemovedForEveryRecognisedName() {
        #expect(ProductName.removingBinary(from: "\(Self.legacy.binary) digest X", recognising: Self.both) == "digest X")
        #expect(ProductName.removingBinary(from: "\(Self.current.binary) digest X", recognising: Self.both) == "digest X")
        #expect(ProductName.removingBinary(from: "\(Self.legacy.binary) digest X", recognising: [Self.current]) == nil)
        #expect(ProductName.removingBinary(from: "\(Self.legacy.binary)x digest X", recognising: Self.both) == nil)
    }

    @Test func aLegacyNamedDigestCallStillNamesItsTarget() {
        let call = "\(Self.legacy.binary) digest Sources/App/Gizmo.swift"

        #expect(AnswerThenRead.digestTarget(of: call, recognising: Self.both) == "Sources/App/Gizmo.swift")
        #expect(AnswerThenRead.digestTarget(of: call, recognising: [Self.current]) == nil)
    }

    @Test func aLegacyNamedHookAnswerIsRowedUnderItsCall() {
        let opening = InPlaceAnswer.openingLine(calls: ["\(Self.legacy.binary) digest Sources/App/Gizmo.swift"])

        let call = AuditVerbs.call(name: "Read", input: ["file_path": "/r/Sources/App/Gizmo.swift"], answerText: opening + "\n\nbody", refused: true, recognising: Self.both)

        #expect(call?.kind == "digest (file) (hook)")
    }

    @Test func aLegacyNamedRunClearsTheEditsBeforeIt() throws {
        let repo = try MCPTestRepo.make(declaring: "Gauge")
        let gauge = repo.appendingPathComponent("Sources/App/Gauge.swift").path
        let lines: [Data] = [
            TranscriptFixture.toolUse("Edit", id: "e1", input: ["file_path": gauge], cwd: repo.path),
            TranscriptFixture.toolResult(id: "e1", isError: false),
            TranscriptFixture.toolUse("Bash", id: "b1", input: ["command": "\(Self.legacy.binary) run -- swift build"], cwd: repo.path),
            TranscriptFixture.toolResult(id: "b1", isError: false),
        ]
        let directory = try TemporaryDirectory.make("recognised-runs")
        let transcript = directory.appendingPathComponent("session.jsonl")
        try Data(lines.flatMap { $0 + [0x0A] }).write(to: transcript)

        let recognised = BuildInputEditsSinceGreenRun.scan(transcript: transcript, skippingSidechains: false, recognising: Self.both)
        let unrecognised = BuildInputEditsSinceGreenRun.scan(transcript: transcript, skippingSidechains: false, recognising: [Self.current])

        #expect(recognised?.files == [])
        #expect(unrecognised?.files == [gauge])
    }
}
