//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers that a server under the current name which runs something else does not count as the current name's registration, with a name stood in for the product's (`gizmo`) whose predecessor is `swift-sure`.
@Suite(.temporaryDirectories)
struct LegacyRegistrationForeignServerTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")

    @Test
    func aForeignServerUnderTheCurrentNameLeavesTheEarlierServerInPlace() throws {
        let home = try TemporaryDirectory.make("foreign-current-server")
        let servers: [String: Any] = [
            "swift-sure": ["command": "/opt/bin/swift-sure", "args": ["mcp"], "type": "stdio"] as [String: Any],
            "gizmo": ["command": "/opt/other/thing", "args": ["serve"], "type": "stdio"] as [String: Any],
        ]
        let config = home.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: config)
        let rules = home.appendingPathComponent(".claude/rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        let gizmoRule = rules.appendingPathComponent("gizmo.md")
        try Data("rule".utf8).write(to: gizmoRule)
        let locations = SiftUninstall.Locations(
            settings: home.appendingPathComponent(".claude/settings.json"),
            claudeConfig: config,
            rule: gizmoRule,
            siftHome: home.appendingPathComponent(".gizmo"),
            logs: []
        )
        let asked = Asked()

        let result = LegacyRegistrationCleanup.settle(locations, names: [Self.gizmo, Self.older]) { name, _ in
            asked.names.append(name)
            return .removed
        }

        #expect(asked.names.isEmpty)
        #expect(!result.removed)
        #expect(result.lines.contains { $0.hasPrefix("mcp:") && $0.contains("was left, since") && $0.contains("is not registered") })
    }
}

private extension LegacyRegistrationForeignServerTests {
    final class Asked: @unchecked Sendable {
        var names: [ProductName] = []
    }
}
