//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers a nested typealias writing a name only an `exclude:`d file of its own module declares, with no index store.
///
/// A file a SwiftPM target leaves out is never compiled, so its declaration is no certain one of the module that holds its directory.
@Suite(.temporaryDirectories)
struct WhereExcludedFileReachTests {
    private static var gizmo: String {
        """
        struct Gizmo {
            init(_ name: String) {}
        }
        """
    }

    private static var shelf: String {
        """
        enum Shelf {
            typealias Bin = Gizmo
        }
        extension Shelf {
            func one() { _ = Bin("t") }
        }
        """
    }

    private static func lookup(_ symbol: String, libOptions: String) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Multi",
                targets: [
                    .target(name: "App"),
                    .target(name: "Lib"\(libOptions)),
                ]
            )
            """,
            to: "Package.swift",
            in: root
        )
        try TestSources.write(gizmo, to: "Sources/App/Types.swift", in: root)
        try TestSources.write(gizmo, to: "Sources/Lib/Gizmo.swift", in: root)
        try TestSources.write(shelf, to: "Sources/Lib/Shelf.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let engine = try SiftEngine(directory: root)
        let freshness = try await engine.ensureFresh()
        return try await engine.lookup(symbol: symbol, freshness: freshness)
    }

    /// A declaration in a file its target excludes is no certain own-module declaration, so the alias writing the name stays a use not proven to name another module's type.
    @Test
    func anAliasOfAnExcludedFilesTypeIsNotFoldedAsProven() async throws {
        let output = try await Self.lookup("App.Gizmo", libOptions: ", exclude: [\"Gizmo.swift\"]")

        #expect(!output.contains("folded in here"), "\(output)")
        #expect(output.contains("a typealias writing a name another declaration shares, kept as a use though not proven to name it"), "\(output)")
    }

    /// The excluded file's type is no declaration of Lib, so asking for it as Lib's folds nothing, and asked as the module its directory guesses it keeps the alias.
    @Test
    func theExcludedFilesTypeIsNotLibsAndKeepsTheAlias() async throws {
        let asLib = try await Self.lookup("Lib.Gizmo", libOptions: ", exclude: [\"Gizmo.swift\"]")
        let asGuessed = try await Self.lookup("Sources.Gizmo", libOptions: ", exclude: [\"Gizmo.swift\"]")

        #expect(!asLib.contains("folded in here"), "\(asLib)")
        #expect(asLib.contains("could not resolve the path Lib.Gizmo"), "\(asLib)")
        #expect(!asGuessed.contains("folded in here"), "\(asGuessed)")
        #expect(asGuessed.contains("kept as a use though not proven to name it"), "\(asGuessed)")
    }

    /// The same shape without the `exclude:` folds the alias, which shows the fixture reaches the own-module rule.
    @Test
    func theSameAliasWithNoExcludeIsFolded() async throws {
        let output = try await Self.lookup("Lib.Gizmo", libOptions: "")

        #expect(output.contains("folded in here"), "\(output)")
    }

    /// The other module's own declaration of the name keeps the alias's uses among its own, as no proof moved them elsewhere.
    @Test
    func theOtherModulesDeclarationStillListsTheAliasUses() async throws {
        let output = try await Self.lookup("App.Gizmo", libOptions: ", exclude: [\"Gizmo.swift\"]")

        #expect(output.contains("Sources/Lib/Shelf.swift (2):"), "\(output)")
        #expect(output.contains("typealias Bin = Gizmo"), "\(output)")
    }
}
