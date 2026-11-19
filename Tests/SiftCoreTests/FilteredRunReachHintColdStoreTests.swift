//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the `filtered:` line over a built checkout whose index store has no cache yet, as every clone or copy of a checkout has: the line is still given, by written name, and the store is not opened for it.
@Suite(.serialized, .temporaryDirectories)
struct FilteredRunReachHintColdStoreTests {
    /// `WidgetTests` and `GadgetTests` use `Lib.Widget`; `BystanderTests` writes the name but means a type of its own, so only a walk by written name reaches it.
    ///
    /// Built after the edit, as a `swift test` run builds before its line is made.
    private static func builtCheckout() async throws -> URL {
        let root = try await FilteredRunReachHintTests.checkout(dirty: false)
        let bystander = "import XCTest\n@testable import Lib\n\nfinal class BystanderTests: XCTestCase {\n    private struct Widget {}\n\n    func testExample() {\n        _ = Widget()\n    }\n}\n"
        try TestSources.write(bystander, to: "Tests/LibTests/BystanderTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "bystander")
        try await SiftEngine(directory: root).ensureFresh()
        try TestSources.write("public struct Widget {\n    public init() {}\n    public var size = 1\n}\n", to: "Sources/Lib/Core.swift", in: root)
        try await TestSources.swiftBuild(packageAt: root, includingTests: true)
        return root
    }

    private static func caches(in root: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: SemanticCache.root(in: SiftPaths.cache(in: root)).path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
    }

    /// A cold store's import can take the whole budget, so the line never waits on one: it is given by written name, the same on every run while the store stays cold, and no cache is made for it.
    @Test
    func aStoreWithNoCacheGivesTheLineByWrittenNameWithoutOpeningIt() async throws {
        let root = try await Self.builtCheckout()

        let first = try FilteredRunReachHintTests.lines(FilteredRunReachHintTests.widgetNames, arguments: FilteredRunReachHintTests.oneFilter, root: root)
        let second = try FilteredRunReachHintTests.lines(FilteredRunReachHintTests.widgetNames, arguments: FilteredRunReachHintTests.oneFilter, root: root)

        #expect(first == ["  filtered: the working tree changes Core.swift; 2 suites reaching it did not run — run swift test --filter WidgetTests --filter LibTests.BystanderTests --filter LibTests.GadgetTests (swift-sure affected lists every suite)"])
        #expect(second == first)
        #expect(Self.caches(in: root).isEmpty)
    }

    /// Once an earlier query has opened the store, the line reads it and leaves out the suite that only writes the name.
    @Test
    func aStoreWithACacheGivesTheLineByResolvedReference() async throws {
        let root = try await Self.builtCheckout()
        try await SiftEngine(directory: root).awaitSemanticStore()
        #expect(!Self.caches(in: root).isEmpty)

        let lines = try FilteredRunReachHintTests.lines(FilteredRunReachHintTests.widgetNames, arguments: FilteredRunReachHintTests.oneFilter, root: root)

        #expect(lines == ["  filtered: the working tree changes Core.swift; 1 suite reaching it did not run — run swift test --filter WidgetTests --filter LibTests.GadgetTests (swift-sure affected lists every suite)"])
    }
}
