//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers that an earlier name's server and rule come out only once the current name's are in place, with a name stood in for the product's (`gizmo`) whose predecessor is `swift-sure`.
@Suite(.temporaryDirectories)
struct LegacyRegistrationGateTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]

    private static func setup(in home: URL, currentServer: Bool, currentRule: Bool) throws -> Setup {
        var servers: [String: Any] = ["swift-sure": ["command": "/opt/bin/swift-sure", "args": ["mcp"], "type": "stdio"] as [String: Any]]
        if currentServer {
            servers["gizmo"] = ["command": "/opt/bin/gizmo", "args": ["mcp"], "type": "stdio"] as [String: Any]
        }
        let config = home.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: config)
        let rules = home.appendingPathComponent(".claude/rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        let olderRule = rules.appendingPathComponent("swift-sure.md")
        let gizmoRule = rules.appendingPathComponent("gizmo.md")
        try Data("rule".utf8).write(to: olderRule)
        if currentRule {
            try Data("rule".utf8).write(to: gizmoRule)
        }
        let locations = SiftUninstall.Locations(
            settings: home.appendingPathComponent(".claude/settings.json"),
            claudeConfig: config,
            rule: gizmoRule,
            siftHome: home.appendingPathComponent(".gizmo"),
            logs: []
        )
        return Setup(locations: locations, olderRule: olderRule, gizmoRule: gizmoRule)
    }

    @Test
    func anEarlierServerStaysUntilTheCurrentOneIsRegistered() throws {
        let home = try TemporaryDirectory.make("gate-server-absent")
        let setup = try Self.setup(in: home, currentServer: false, currentRule: true)
        let asked = Asked()

        let result = LegacyRegistrationCleanup.settle(setup.locations, names: Self.names) { name, _ in
            asked.names.append(name)
            return .removed
        }

        #expect(asked.names.isEmpty)
        #expect(result.lines.contains { $0.hasPrefix("mcp:") && $0.contains("run: gizmo install") })
    }

    @Test
    func anEarlierServerIsRemovedOnceTheCurrentOneIsRegistered() throws {
        let home = try TemporaryDirectory.make("gate-server-present")
        let setup = try Self.setup(in: home, currentServer: true, currentRule: true)
        let asked = Asked()

        let result = LegacyRegistrationCleanup.settle(setup.locations, names: Self.names) { name, _ in
            asked.names.append(name)
            return .removed
        }

        #expect(asked.names == [Self.older])
        #expect(result.removed)
    }

    @Test
    func anEarlierRuleStaysUntilTheCurrentOneExists() throws {
        let home = try TemporaryDirectory.make("gate-rule-absent")
        let setup = try Self.setup(in: home, currentServer: true, currentRule: false)

        let result = LegacyRegistrationCleanup.settle(setup.locations, names: Self.names) { _, _ in .removed }

        #expect(FileManager.default.fileExists(atPath: setup.olderRule.path))
        #expect(result.lines.contains { $0.hasPrefix("rule:") && $0.contains("run: gizmo install") })
    }

    @Test
    func anEarlierRuleIsRemovedOnceTheCurrentOneExists() throws {
        let home = try TemporaryDirectory.make("gate-rule-present")
        let setup = try Self.setup(in: home, currentServer: true, currentRule: true)

        let result = LegacyRegistrationCleanup.settle(setup.locations, names: Self.names) { _, _ in .removed }

        #expect(!FileManager.default.fileExists(atPath: setup.olderRule.path))
        #expect(result.lines.contains { $0.hasPrefix("rule: removed") })
    }
}

private extension LegacyRegistrationGateTests {
    struct Setup {
        let locations: SiftUninstall.Locations
        let olderRule: URL
        let gizmoRule: URL
    }

    final class Asked: @unchecked Sendable {
        var names: [ProductName] = []
    }
}
