//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers every place that names the tool's directory in a repository, with a name stood in for the product's (`gizmo`) whose predecessor (`swift-sure`) left the directory behind: each resolves to what is there and none creates a second one.
@Suite(.temporaryDirectories)
struct LegacyDirectoryResolutionTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]

    @Test
    func aRegularFileOfAnOlderNameIsNotTheCacheDirectory() throws {
        let root = try TemporaryDirectory.make("legacy-file")
        try Data("x".utf8).write(to: root.appendingPathComponent(".swift-sure"))

        #expect(SiftPaths.cache(in: root, names: Self.names).lastPathComponent == ".gizmo")
        let home = try TemporaryDirectory.make("legacy-file-home")
        try Data("x".utf8).write(to: home.appendingPathComponent(".swift-sure"))
        #expect(SiftPaths.home(environment: ["CFFIXED_USER_HOME": home.path], names: Self.names).lastPathComponent == ".gizmo")
    }

    @Test
    func aDirectoryOfAnOlderNameIsNotTheConfigFile() throws {
        let root = try TemporaryDirectory.make("legacy-config-dir")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".swift-sure.json"), withIntermediateDirectories: true)

        #expect(SiftPaths.config(in: root, names: Self.names).lastPathComponent == ".gizmo.json")
    }

    @Test
    func theDirectoryNamesListEveryNameGivenCurrentFirst() {
        #expect(SiftPaths.directoryNames(names: Self.names) == [".gizmo", ".swift-sure"])
    }

    @Test
    func aWalkSkipsTheOlderNamesDirectoryToo() throws {
        let root = try TemporaryDirectory.make("legacy-walk")
        for name in [".swift-sure", "build"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        let walk = InTreeStoreWalk.walk(repoRoot: root, ignored: [".swift-sure", "build"], names: Self.names)
        let skippedOnlyForTheCurrentName = InTreeStoreWalk.walk(repoRoot: root, ignored: [".swift-sure", "build"], names: [Self.gizmo])

        #expect(walk.visited < skippedOnlyForTheCurrentName.visited)
    }

    @Test
    func aSetAsideTreatsAnOlderNamesDirectoryAsTheToolsOwn() throws {
        let output = Data("? .swift-sure/index.db\0? Sources/a.swift\0".utf8)

        let parsed = try SetAsideStatusLine.parse(output, flag: "--without", names: Self.names)
        let current = try SetAsideStatusLine.parse(output, flag: "--without", names: [Self.gizmo])

        #expect(parsed.own == [".swift-sure/index.db"])
        #expect(parsed.lines.map(\.path) == ["Sources/a.swift"])
        #expect(current.own.isEmpty)
    }

    @Test
    func theExcludeEntryNamesTheOlderDirectoryWhereOnlyThatOneExists() throws {
        let root = try TemporaryDirectory.make("legacy-exclude")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".swift-sure"), withIntermediateDirectories: true)
        let common = root.appendingPathComponent("common")

        #expect(GitContext(repoRoot: root).cacheIsExcluded(inCommonDirectory: common, names: Self.names))

        let exclude = try String(contentsOf: common.appendingPathComponent("info/exclude"), encoding: .utf8)
        #expect(exclude == ".swift-sure/\n")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".gizmo").path))
    }

    @Test
    func theWorktreeBuildIsFoundUnderTheOlderDirectory() throws {
        let root = try TemporaryDirectory.make("legacy-derived")
        let discovery = IndexStoreDiscovery(repoRoot: root, config: SiftConfig(), derivedDataRoot: root.appendingPathComponent("no-dd"))
        #expect(discovery.siftDerivedData(names: Self.names) == ".gizmo/DerivedData")

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".swift-sure"), withIntermediateDirectories: true)
        #expect(discovery.siftDerivedData(names: Self.names) == ".swift-sure/DerivedData")
    }

    @Test
    func anOlderNamesDirectoryIsListedAsLeftBehind() throws {
        let root = try TemporaryDirectory.make("legacy-left")
        let cache = root.appendingPathComponent(".swift-sure")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let locations = SiftUninstall.Locations(
            settings: root.appendingPathComponent("settings.json"),
            claudeConfig: root.appendingPathComponent(".claude.json"),
            rule: root.appendingPathComponent("rules/gizmo.md"),
            siftHome: root.appendingPathComponent("home/.gizmo"),
            logs: []
        )

        let listed = SiftUninstall.leftCaches(locations, roots: [root.path], names: Self.names)
        let currentOnly = SiftUninstall.leftCaches(locations, roots: [root.path], names: [Self.gizmo])

        #expect(listed.map(\.directory.lastPathComponent) == [".swift-sure"])
        #expect(currentOnly.isEmpty)
    }
}
