//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// `swift-sure pre-tool-use --agent cursor` on a Cursor `Shell` build, driven through the built binary: rewritten in place to `swift-sure run -- …` unless Cursor's own rules speak for the line, and never refused.
@Suite(.temporaryDirectories)
struct CursorBuildRewriteTests {
    /// With no Cursor rules at all, the build is rewritten: the whole input goes back with the command wrapped and no permission named, so Cursor applies its own approval.
    @Test
    func aBuildWithNoRulesIsRewrittenInPlace() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let run = try scene.run(scene.cursor("Shell", Self.build))
        let object = try CursorPreToolUseTests.object(run.printed)

        #expect(run.status == 0)
        #expect(Set(object.keys) == ["updated_input"])
        let input = try #require(object["updated_input"] as? [String: Any])
        #expect(input["command"] as? String == "swift-sure run -- swift test")
        #expect(input["cwd"] as? String == "")
        #expect(input["timeout"] as? Int == 30000)
        #expect(Set(input.keys) == ["command", "cwd", "timeout"])
    }

    /// A build that an allow rule covers as written, and the wrapping too, is rewritten.
    @Test
    func aBuildWhoseWrappingIsAllowedIsRewritten() throws {
        let scene = try CursorPreToolUseTests.Scene()
        try Self.write(#"{"permissions": {"allow": ["Shell(swift)", "Shell(swift-sure)"]}}"#, in: scene.repo)
        let run = try scene.run(scene.cursor("Shell", Self.build))
        let input = try #require(CursorPreToolUseTests.object(run.printed)["updated_input"] as? [String: Any])

        #expect(input["command"] as? String == "swift-sure run -- swift test")
    }

    /// Where a deny rule names the build or its wrapping, an allow rule covers it as written but not the wrapping, or the rules cannot be read, the build runs as written: nothing printed, so nothing refused.
    @Test(arguments: [
        #"{"permissions": {"deny": ["Shell(swift)"]}}"#,
        #"{"permissions": {"deny": ["Shell(swift-sure)"]}}"#,
        #"{"permissions": {"deny": ["Shell(swift-sure:run*)"]}}"#,
        #"{"permissions": {"allow": ["Shell(swift)"]}}"#,
        "not json {",
    ])
    func aBuildTheRulesSpeakForRunsAsWritten(rules: String) throws {
        let scene = try CursorPreToolUseTests.Scene()
        try Self.write(rules, in: scene.repo)
        let run = try scene.run(scene.cursor("Shell", Self.build))

        #expect(run.status == 0)
        #expect(run.printed.isEmpty, "printed \(run.printed)")
    }
}

extension CursorBuildRewriteTests {
    /// A Cursor `Shell` input for `swift test`, in the shape a probe recorded.
    static var build: [String: Any] {
        ["command": "swift test", "cwd": "", "timeout": 30000]
    }

    /// Writes `rules` as the project's Cursor permission file in `repo`.
    static func write(_ rules: String, in repo: URL) throws {
        let directory = repo.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try rules.write(to: directory.appendingPathComponent("cli.json"), atomically: true, encoding: .utf8)
    }
}
