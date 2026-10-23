//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// Covers where a coverage run's result bundle goes when an earlier release's directory (`.swift-sure`, where the product is `gizmo`) is the one the tree has.
@Suite(.temporaryDirectories)
struct XcodebuildCoverageLegacyDirectoryTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]

    @Test
    func theBundleIsNamedUnderTheDirectoryTheTreeHas() throws {
        let tree = try TemporaryDirectory.make("coverage-legacy-name")

        #expect(XcodebuildCoverage.ownResultBundle(run: "7", in: tree, names: Self.names) == ".gizmo/coverage-7.xcresult")

        try FileManager.default.createDirectory(at: tree.appendingPathComponent(".swift-sure"), withIntermediateDirectories: true)
        #expect(XcodebuildCoverage.ownResultBundle(run: "7", in: tree, names: Self.names) == ".swift-sure/coverage-7.xcresult")
    }

    @Test
    func aRunClearsItsOwnBundleAndAbandonedOnesInTheOlderDirectoryAndCreatesNoOtherDirectory() throws {
        let tree = try TemporaryDirectory.make("coverage-legacy-clear")
        let directory = tree.appendingPathComponent(".swift-sure")
        let own = directory.appendingPathComponent("coverage-7.xcresult")
        let abandoned = directory.appendingPathComponent("coverage-3.xcresult")
        for bundle in [own, abandoned] {
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        }
        let old = Date().addingTimeInterval(-3 * RunLedger.trustWindow)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: abandoned.path)
        let arguments = XcodebuildCoverage.enabling(["xcodebuild", "test"], run: "7", in: tree, names: Self.names)

        XcodebuildCoverage.clearOwnResultBundle(for: arguments, in: tree, run: "7", names: Self.names)

        #expect(arguments.last == ".swift-sure/coverage-7.xcresult")
        #expect(!FileManager.default.fileExists(atPath: own.path))
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(!FileManager.default.fileExists(atPath: tree.appendingPathComponent(".gizmo").path))
    }
}
