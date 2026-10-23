//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// `install-hook` registers `swift-sure stop` for `Stop` and `SubagentStop`, and `uninstall-hook` takes out exactly those two.
@Suite(.temporaryDirectories)
struct InstallHookStopTests {
    private static func hooks(at url: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], sourceLocation: sourceLocation)
        return object["hooks"] as? [String: Any] ?? [:]
    }

    /// Registers every event the way `install-hook` does, under a `swift-sure` path the re-run and the uninstall can recognise.
    private static func install(_ settings: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        var current = try? Data(contentsOf: settings)
        for event in SiftClaudeSetup.events {
            current = try SiftClaudeSetup.hooks.apply(to: current, command: "/bin/swift-sure \(event.subcommand)", event: event).data
        }
        try #require(current, sourceLocation: sourceLocation).write(to: settings)
    }

    @Test
    func bothStopEventsRunTheStopCommandOnceWithNoMatcher() throws {
        let settings = try TemporaryDirectory.make("install-stop").appendingPathComponent("settings.json")
        try Self.install(settings)
        try Self.install(settings)

        let hooks = try Self.hooks(at: settings)
        for event in ["Stop", "SubagentStop"] {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.count == 1)
            #expect(entries.first?["matcher"] == nil)
            let inner = try #require(entries.first?["hooks"] as? [[String: Any]])
            #expect(inner.count == 1)
            #expect(inner.first?["command"] as? String == "/bin/swift-sure stop")
        }
    }

    @Test
    func uninstallTakesBothStopEntriesAndLeavesAForeignOne() throws {
        let settings = try TemporaryDirectory.make("install-stop").appendingPathComponent("settings.json")
        let foreign = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.claude/notify.sh"}]}]}}"#
        try foreign.write(to: settings, atomically: true, encoding: .utf8)
        try Self.install(settings)

        try UninstallHookCommand.parse(["--settings", settings.path]).run()

        let hooks = try Self.hooks(at: settings)
        #expect(hooks["SubagentStop"] == nil)
        let remaining = try #require(hooks["Stop"] as? [[String: Any]])
        let commands = remaining.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        #expect(commands == ["~/.claude/notify.sh"])
    }
}
