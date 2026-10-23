//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// Covers the notes the uninstall prints for a registration under an earlier name (`swift-sure`, where the product is `gizmo`) and the state-directory line.
@Suite(.temporaryDirectories)
struct UninstallLegacyNotesTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]

    private static func locations(_ scratch: URL, config: [String: Any]) throws -> SiftUninstall.Locations {
        let file = scratch.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: config).write(to: file)
        return SiftUninstall.Locations(
            settings: scratch.appendingPathComponent("settings.json"),
            claudeConfig: file,
            rule: scratch.appendingPathComponent("rules/gizmo.md"),
            siftHome: scratch.appendingPathComponent(".gizmo"),
            logs: []
        )
    }

    @Test
    func aLocalScopeNoteForAnEarlierNameGivesThatNamesRemoval() throws {
        let scratch = try TemporaryDirectory.make("legacy-local")
        let project = scratch.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let path = CanonicalPath.of(project.path)
        let entry: [String: Any] = ["command": "/opt/bin/swift-sure", "args": ["mcp"], "type": "stdio"]
        let locations = try Self.locations(scratch, config: ["projects": [path: ["mcpServers": ["swift-sure": entry]]]])

        let step = UninstallServers.settle(locations, roots: [], names: Self.names, gitDirectories: { _ in nil }, removeLegacyServer: { _, _ in .failed("refused") }, removeServer: { _ in .removed })

        let note = try #require(step.notes.first)

        #expect(note.contains("claude mcp remove swift-sure --scope local"))
        #expect(!note.contains("gizmo"))
    }

    @Test
    func aProjectFileNamingBothServersKeepsBothNotes() throws {
        let scratch = try TemporaryDirectory.make("legacy-project-file")
        let root = scratch.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let servers: [String: Any] = [
            "gizmo": ["command": "/opt/bin/gizmo", "args": ["mcp"]],
            "swift-sure": ["command": "/opt/bin/swift-sure", "args": ["mcp"]],
        ]
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: root.appendingPathComponent(".mcp.json"))
        let locations = try Self.locations(scratch, config: [:])

        var step = UninstallServers.settle(locations, roots: [root.path], names: Self.names, removeLegacyServer: { _, _ in .removed }, removeServer: { _ in .removed })
        step.markUnrecorded([root.path])

        #expect(step.failures == 2)
        #expect(step.notes.count == 2)
        #expect(step.notes.filter { $0.contains("registers gizmo") && $0.contains("the purge deleted the record") }.count == 1)
        #expect(step.notes.filter { $0.contains("registers swift-sure") && $0.contains("the purge deleted the record") }.count == 1)
    }

    @Test
    func theStateNotePrintsTheDirectoryItWasGiven() throws {
        let home = try TemporaryDirectory.make("state-note")

        let note = try #require(UninstallHookCommand.stateNote(home: home))

        #expect(note.contains(home.path))
        #expect(!note.contains("~"))
        #expect(UninstallHookCommand.stateNote(home: home.appendingPathComponent("absent")) == nil)
    }
}
