//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers that a directory at an earlier release's rule path is reported as not removed by the dry run and the real cleanup alike, with a name stood in for the product's (`gizmo`) whose predecessor is `swift-sure`.
@Suite(.temporaryDirectories)
struct LegacyRuleDirectoryDryRunTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")

    @Test
    func aDirectoryAtTheLegacyRulePathIsNotWouldRemoveInTheDryRunAndSurvivesTheInstall() throws {
        let home = try TemporaryDirectory.make("legacy-rule-directory")
        let rules = home.appendingPathComponent(".claude/rules")
        let legacyRule = rules.appendingPathComponent("swift-sure.md")
        try FileManager.default.createDirectory(at: legacyRule, withIntermediateDirectories: true)
        let inside = legacyRule.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: inside)
        let gizmoRule = rules.appendingPathComponent("gizmo.md")
        try Data("rule".utf8).write(to: gizmoRule)
        let locations = SiftUninstall.Locations(
            settings: home.appendingPathComponent(".claude/settings.json"),
            claudeConfig: home.appendingPathComponent(".claude.json"),
            rule: gizmoRule,
            siftHome: home.appendingPathComponent(".gizmo"),
            logs: []
        )

        let planned = LegacyRegistrationCleanup.pending(locations, names: [Self.gizmo, Self.older], serverRegistered: true, ruleInstalled: true, claudeOnPath: true)
        let result = LegacyRegistrationCleanup.settle(locations, names: [Self.gizmo, Self.older]) { _, _ in .removed }

        #expect(planned.contains("rule: would not remove \(legacyRule.path) — not a plain file"))
        #expect(!planned.contains { $0.contains("would remove \(legacyRule.path)") })
        #expect(result.lines.contains("rule: not removed — \(legacyRule.path) is not a plain file"))
        #expect(!result.removed)
        #expect(FileManager.default.fileExists(atPath: inside.path))
    }
}
