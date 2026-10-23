//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// What an earlier release registered under the name it shipped as is still recognised where the plugin or a Cursor hook file is checked.
@Suite(.temporaryDirectories)
struct LegacyRegistrationRecognitionTests {
    private static func cursorHooks(binary: String) throws -> Data {
        var events: [String: Any] = [:]
        for hook in SiftCursorSetup.hooks.hooks {
            events[hook.event] = [["command": "/opt/old/bin/\(binary) \(SiftCursorSetup.hooks.registeredSubcommand(for: hook))"]]
        }
        return try JSONSerialization.data(withJSONObject: ["version": 1, "hooks": events])
    }

    @Test(arguments: ["sift", "swift-sure"])
    func aCursorHookFileOfEitherNameHoldsAHook(binary: String) throws {
        #expect(try SiftCursorSetup.registersAHook(in: Self.cursorHooks(binary: binary)))
    }

    @Test
    func aCursorHookFileOfAnotherToolHoldsNone() throws {
        #expect(try !SiftCursorSetup.registersAHook(in: Self.cursorHooks(binary: "gizmo")))
    }

    @Test
    func anEarlierReleasesHooksAndServerAreLeftoversTheNewInstallMustClear() throws {
        let home = try TemporaryDirectory.make("legacy-leftovers")
        let environment = InstallCommandHarness.environment(home: home)
        let earlier = try #require(ProductName.legacy.first)
        var settings: Data?
        for event in SiftClaudeSetup.events {
            settings = try SiftClaudeSetup.hooks(named: earlier).apply(to: settings, command: "/opt/old/bin/\(earlier.binary) \(event.subcommand)", event: event).data
        }
        try FileManager.default.createDirectory(at: AgentPaths.claudeSettings(environment: environment).deletingLastPathComponent(), withIntermediateDirectories: true)
        try #require(settings).write(to: AgentPaths.claudeSettings(environment: environment))
        let servers = [earlier.mcpServer: ["command": "/opt/old/bin/\(earlier.binary)", "args": ["mcp"]]]
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: AgentPaths.claudeConfig(environment: environment))

        #expect(ClaudePluginState(environment: environment).installerLeftovers == ["hooks", "MCP entry"])
    }
}
