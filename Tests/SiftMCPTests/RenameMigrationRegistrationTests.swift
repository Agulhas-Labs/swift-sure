//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// Covers the registrations an older release left in the agent's settings, with a name stood in for the product's (`gizmo`) whose predecessor is `swift-sure`.
@Suite(.temporaryDirectories)
struct RenameMigrationRegistrationTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]

    /// A settings file holding the hooks the older release registered for `binary`.
    private static func settingsWithOlderHooks(in scratch: URL, binary: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        let settings = scratch.appendingPathComponent("settings.json")
        var data: Data?
        for event in SiftClaudeSetup.events {
            data = try SiftClaudeSetup.hooks(named: older).apply(to: data, command: "\(binary) \(event.subcommand)", event: event).data
        }
        try #require(data, sourceLocation: sourceLocation).write(to: settings)
        return settings
    }

    private static func commands(in settings: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String] {
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any], sourceLocation: sourceLocation)
        let hooks = object["hooks"] as? [String: Any] ?? [:]
        return hooks.values.flatMap { ($0 as? [[String: Any]] ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } } }
    }

    @Test
    func uninstallRemovesTheHooksAnOlderReleaseRegistered() throws {
        let scratch = try TemporaryDirectory.make("migrate-hooks")
        let settings = try Self.settingsWithOlderHooks(in: scratch, binary: "/opt/bin/swift-sure")
        #expect(try !Self.commands(in: settings).isEmpty)

        let outcome = try HookUninstall.run(settings: settings, onlyAdvice: false, names: Self.names)

        #expect(outcome.changed)
        #expect(try Self.commands(in: settings).isEmpty)
    }

    @Test
    func uninstallLeavesAnOlderReleasesHooksWhereTheNameIsNotRecognised() throws {
        let scratch = try TemporaryDirectory.make("migrate-hooks-kept")
        let settings = try Self.settingsWithOlderHooks(in: scratch, binary: "/opt/bin/swift-sure")

        let outcome = try HookUninstall.run(settings: settings, onlyAdvice: false, names: [Self.gizmo])

        #expect(!outcome.changed)
        #expect(try !Self.commands(in: settings).isEmpty)
    }

    @Test
    func uninstallRemovesTheServerAnOlderReleaseRegistered() throws {
        let scratch = try TemporaryDirectory.make("migrate-server")
        let config = scratch.appendingPathComponent(".claude.json")
        let entry: [String: Any] = ["command": "/opt/bin/swift-sure", "args": ["mcp"], "type": "stdio"]
        try JSONSerialization.data(withJSONObject: ["mcpServers": ["swift-sure": entry]]).write(to: config)
        let locations = SiftUninstall.Locations(
            settings: scratch.appendingPathComponent("settings.json"),
            claudeConfig: config,
            rule: scratch.appendingPathComponent("rules/swift-sure.md"),
            siftHome: scratch.appendingPathComponent(".swift-sure"),
            logs: []
        )
        var asked: [(ProductName, SiftUninstall.ServerScope)] = []

        let step = UninstallServers.settle(locations, roots: [], names: Self.names, removeLegacyServer: { name, scope in
            asked.append((name, scope))
            try? JSONSerialization.data(withJSONObject: ["mcpServers": [String: Any]()]).write(to: config)
            return .removed
        }, removeServer: { _ in .removed })

        #expect(asked.map(\.0) == [Self.older])
        #expect(asked.first?.1 == .user)
        #expect(step.removed.count == 1)
        #expect(step.failures == 0)
    }

    @Test
    func installReplacesTheHooksAnOlderReleaseRegistered() throws {
        let scratch = try TemporaryDirectory.make("migrate-install")
        let settings = try Self.settingsWithOlderHooks(in: scratch, binary: "/opt/bin/swift-sure")
        let binary = try InstallHookBinaryPathTests.executable(at: "bin/gizmo", in: scratch)
        var command = try InstallHookCommand.parse(["--settings", settings.path, "--no-allow-run"])
        let recorded = RecordedOutput()
        command.output = recorded.output
        command.names = Self.names
        command.arguments = [binary.path, "install-hook"]
        command.environment = ["PATH": binary.deletingLastPathComponent().path, "CFFIXED_USER_HOME": scratch.path]
        command.executable = binary.path

        try command.run()

        let registered = try Self.commands(in: settings)

        #expect(!registered.isEmpty)
        #expect(registered.allSatisfy { $0.hasPrefix(binary.path + " ") })
    }

    @Test
    func aBinaryRunUnderAnOlderNameRegistersTheCurrentNamesPathBesideIt() throws {
        let scratch = try TemporaryDirectory.make("migrate-alias")
        let older = try InstallHookBinaryPathTests.executable(at: "bin/swift-sure", in: scratch)
        let environment = ["PATH": older.deletingLastPathComponent().path, "CFFIXED_USER_HOME": scratch.path]

        let alone = InstallHookCommand.binaryPath(invokedAs: older.path, environment: environment, executable: older.path, names: Self.names)
        let current = try InstallHookBinaryPathTests.executable(at: "bin/gizmo", in: scratch)
        let beside = InstallHookCommand.binaryPath(invokedAs: older.path, environment: environment, executable: older.path, names: Self.names)

        #expect(alone == older.path)
        #expect(beside == current.path)
    }
}
