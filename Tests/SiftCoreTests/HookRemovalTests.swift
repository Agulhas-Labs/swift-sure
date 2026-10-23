//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the status line an older install registered, which the install and the uninstall both take out of `settings.json` and nothing else.
struct HookRemovalTests {
    private static func settings(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private static func object(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
    }

    // MARK: - Status line

    @Test
    func ourStatusLineIsRemovedAtAnyPath() throws {
        let command = "/anywhere/swift-sure statusline"
        let existing = try Self.settings(["theme": "dark", "statusLine": ["type": "command", "command": command]])

        let removal = try StatuslineRegistration.remove(from: existing)

        guard case let .removed(data, removed) = removal else {
            Issue.record("expected \(command) to be recognised as ours, got \(removal)")
            return
        }

        #expect(removed == command)
        #expect(try Self.object(data)["statusLine"] == nil)
        #expect(try Self.object(data)["theme"] as? String == "dark")
    }

    /// The single slot cuts the same way on the way out: taking someone's own status line is worse than leaving ours behind.
    @Test
    func aStatusLineSomeoneElseBuiltIsLeftAlone() throws {
        let existing = try Self.settings(["statusLine": ["type": "command", "command": "~/.claude/my-statusline.sh"]])

        #expect(try StatuslineRegistration.remove(from: existing) == .notOurs(existing: "~/.claude/my-statusline.sh"))
    }

    /// A slot holding something of an unrecognised shape is reported, never emptied — it cannot be ours, so it is someone's.
    @Test
    func aStatusLineOfAnUnrecognisedShapeIsLeftAlone() throws {
        let existing = try Self.settings(["statusLine": "my-statusline.sh"])

        #expect(try StatuslineRegistration.remove(from: existing) == .notOurs(existing: "(a status line of an unrecognised shape)"))
    }

    @Test
    func anEmptySlotIsNothingToUndo() throws {
        #expect(try StatuslineRegistration.remove(from: nil) == .absent)
        #expect(try StatuslineRegistration.remove(from: Self.settings(["theme": "dark"])) == .absent)
    }

    @Test
    func removingAStatusLineTwiceIsTheSecondTimeANoOp() throws {
        let existing = try Self.settings(["statusLine": ["type": "command", "command": "/bin/swift-sure statusline"]])

        guard case let .removed(data, _) = try StatuslineRegistration.remove(from: existing) else {
            Issue.record("expected the first removal to take it out")
            return
        }

        #expect(try StatuslineRegistration.remove(from: data) == .absent)
    }
}
