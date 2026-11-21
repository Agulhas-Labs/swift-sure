//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the `filtered:` line on a tree whose dirty files `affected` reads as comment-only: they seed nothing and are not named.
@Suite(.serialized, .temporaryDirectories)
struct FilteredRunReachCommentOnlyTests {
    @Test
    func aCommentOnlyEditGetsNoLine() async throws {
        let root = try await FilteredRunReachHintTests.checkout(dirty: false)
        try TestSources.write("// A widget.\npublic struct Widget {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)

        #expect(try FilteredRunReachHintTests.lines(FilteredRunReachHintTests.widgetNames, arguments: FilteredRunReachHintTests.oneFilter, root: root).isEmpty)
    }

    @Test
    func aMixedTreeNamesOnlyTheFileWithARealChange() async throws {
        let root = try await FilteredRunReachHintTests.checkout(dirty: false)
        try TestSources.write("public enum Depot {\n    public static let widget = Widget()\n}\n", to: "Sources/Lib/Depot.swift", in: root)
        try TestSources.write("import XCTest\n@testable import Lib\n\nfinal class DepotKitTests: XCTestCase {\n    func testA() {\n        _ = Depot.widget\n    }\n}\n", to: "Tests/LibTests/DepotKitTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "depot")
        try await SiftEngine(directory: root).ensureFresh()
        try TestSources.write("// A widget.\npublic struct Widget {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        try TestSources.write("public enum Depot {\n    public static let widget = Widget()\n    public static let size = 1\n}\n", to: "Sources/Lib/Depot.swift", in: root)

        let lines = try FilteredRunReachHintTests.lines(FilteredRunReachHintTests.widgetNames, arguments: FilteredRunReachHintTests.oneFilter, root: root)

        #expect(lines == ["  filtered: the working tree changes Depot.swift; 1 suite reaching it did not run — run swift test --filter LibTests.DepotKitTests (swift-sure affected lists every suite)"])
    }
}
