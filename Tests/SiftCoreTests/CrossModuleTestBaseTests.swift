//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers an XCTest case that reaches `XCTestCase` through intermediate bases, one of them in another module, from a file that imports only that module: its tests are declared and named, and the bases, which declare no test of their own, are never offered as a test, a suite or a filter.
@Suite(.temporaryDirectories)
struct CrossModuleTestBaseTests {
    /// An index over `files`, each one's module the directory under `Sources/` or `Tests/` that holds it, as SwiftPM lays a package out.
    private static func store(_ files: [(path: String, source: String)]) throws -> (store: IndexStore, root: URL) {
        let root = try TemporaryDirectory.make("cross-module")
        let store = try TestSources.makeStore()
        let parsed = try files.map { try TestSources.parsed($0.source, path: $0.path, in: root) }
        try store.replaceFiles(parsed) { path in
            (path.split(separator: "/").dropFirst().first.map(String.init) ?? path, false)
        }
        return (store, root)
    }

    /// The test or suite the declaration at `line` of `path` belongs to.
    private static func test(at line: Int, in path: String, store: IndexStore) throws -> TestDeclaration? {
        let reader = TestSymbolReader(store: store)
        guard let enclosing = try reader.enclosingSymbol(path: path, line: line) else { return nil }
        return try reader.testSymbol(enclosing: enclosing)
    }

    /// A root base with no tests in a support module, a middle base with no tests in the test target, and a case whose file imports only the support module.
    private static var chain: [(path: String, source: String)] {
        [
            (
                "Sources/GizmoKit/BaseCase.swift",
                """
                import XCTest

                open class BaseCase: XCTestCase {
                    open func polish() {}
                }
                """
            ),
            (
                "Tests/LibTests/Fixture.swift",
                """
                import XCTest
                @_spi(Testing) import GizmoKit

                class Fixture: BaseCase {
                    func shine() {}
                }
                """
            ),
            (
                "Tests/LibTests/WidgetTests.swift",
                """
                @_spi(Testing) import GizmoKit

                final class WidgetTests: Fixture {
                    func testPolishes() {
                        polish()
                    }

                    func testOne() {
                        shine()
                    }
                }
                """
            ),
        ]
    }

    /// The case's tests are declared under it although its own file imports no testing library, and neither base, which runs no test, is declared at all.
    @Test
    func aCaseReachingXCTestCaseThroughAnotherModulesBaseDeclaresItsTestsAndTheBasesNone() throws {
        let (store, root) = try Self.store(Self.chain)

        let inventory = try TestInventory.read(store: store, repositoryRoot: root)

        #expect(inventory.tests.map { "\($0.target)/\($0.suite)/\($0.function)" } == [
            "LibTests/WidgetTests/testOne()",
            "LibTests/WidgetTests/testPolishes()",
        ])
        #expect(inventory.tests.allSatisfy { $0.style == .xcTest && $0.disposition == .runs })
    }

    /// A line in the case names its test, or the case where it sits in the case's own surface; a line in either base names nothing, so the walk goes on to the case that inherits it.
    @Test
    func aLineInATestlessBaseNamesNoTestAndALineInTheCaseNamesIts() throws {
        let (store, _) = try Self.store(Self.chain)

        let test = try #require(try Self.test(at: 5, in: "Tests/LibTests/WidgetTests.swift", store: store))
        let suite = try #require(try Self.test(at: 3, in: "Tests/LibTests/WidgetTests.swift", store: store))

        #expect(test.symbol.onlyTestingArgument == "-only-testing:LibTests/WidgetTests/testPolishes")
        #expect(suite.symbol.onlyTestingArgument == "-only-testing:LibTests/WidgetTests")
        #expect(try Self.test(at: 5, in: "Tests/LibTests/Fixture.swift", store: store) == nil)
        #expect(try Self.test(at: 4, in: "Sources/GizmoKit/BaseCase.swift", store: store) == nil)
    }

    /// A user type named `XCTestCase`, written where no file imports XCTest, makes nothing a test: not a class naming it directly, and not one reaching it through a base whose file names it without the import, even from a file that imports XCTest itself.
    @Test
    func aStrayTypeNamedXCTestCaseMakesNothingATest() throws {
        let (store, root) = try Self.store([
            ("Tests/LibTests/Stray.swift", "class XCTestCase {}\n\nclass Fixture: XCTestCase {}\n"),
            ("Tests/LibTests/GizmoTests.swift", "final class GizmoTests: XCTestCase {\n    func testOne() {}\n}\n"),
            ("Tests/LibTests/GadgetTests.swift", "import XCTest\n\nfinal class GadgetTests: Fixture {\n    func testTwo() {}\n}\n"),
        ])

        let inventory = try TestInventory.read(store: store, repositoryRoot: root)

        #expect(inventory.tests.isEmpty, "\(inventory.tests.map(\.function))")
        #expect(try Self.test(at: 2, in: "Tests/LibTests/GizmoTests.swift", store: store) == nil)
        #expect(try Self.test(at: 4, in: "Tests/LibTests/GadgetTests.swift", store: store) == nil)
    }

    /// A case whose every test is written in an extension still runs them, so it is still a suite: a line in its own body names it.
    @Test
    func aCaseWhoseTestsAreAllInAnExtensionIsStillASuite() throws {
        let (store, root) = try Self.store([
            ("Tests/LibTests/GadgetTests.swift", "import XCTest\n\nfinal class GadgetTests: XCTestCase {\n    let widget = 1\n}\n"),
            ("Tests/LibTests/GadgetTests+Polish.swift", "import XCTest\n\nextension GadgetTests {\n    func testPolishes() {}\n}\n"),
        ])

        let inventory = try TestInventory.read(store: store, repositoryRoot: root)
        let suite = try #require(try Self.test(at: 4, in: "Tests/LibTests/GadgetTests.swift", store: store))

        #expect(inventory.tests.map { "\($0.suite)/\($0.function)" } == ["GadgetTests/testPolishes()"])
        #expect(suite.symbol.onlyTestingArgument == "-only-testing:LibTests/GadgetTests")
    }

    /// A package whose `LibTests` case inherits a `GizmoKit` base through a test-target base, every file committed, then `edit` applied uncommitted.
    private static func engine(editing edit: (path: String, source: String)) async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        let files = [
            "Package.swift": """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Lib",
                targets: [
                    .target(name: "Lib"),
                    .target(name: "GizmoKit"),
                    .testTarget(name: "LibTests", dependencies: ["Lib", "GizmoKit"]),
                ]
            )
            """,
            "Sources/Lib/Core.swift": "public struct Widget {\n    public init() {}\n}\n",
            "Sources/GizmoKit/BaseCase.swift": "import XCTest\n\nopen class BaseCase: XCTestCase {\n    open func polish() {}\n}\n",
            "Tests/LibTests/Fixture.swift": "import XCTest\n@testable import Lib\n@_spi(Testing) import GizmoKit\n\nclass Fixture: BaseCase {\n    func makeGizmo() -> Widget {\n        Widget()\n    }\n}\n",
            "Tests/LibTests/WidgetTests.swift": "@_spi(Testing) import GizmoKit\n\nfinal class WidgetTests: Fixture {\n    func testPolishes() {\n        _ = makeGizmo()\n    }\n\n    func testOne() {\n        polish()\n    }\n}\n",
        ]
        for (file, source) in files {
            try TestSources.write(source, to: file, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write(edit.source, to: edit.path, in: root)
        let engine = try SiftEngine(directory: root)
        try await engine.awaitSemanticStore()
        _ = try await engine.ensureFresh()
        return engine
    }

    /// A change the middle base's helper reaches is reported through the case's test that calls the helper, never as the base itself.
    @Test
    func affectedNamesTheCasesTestAndNeverATestlessBase() async throws {
        let engine = try await Self.engine(editing: ("Sources/Lib/Core.swift", "public struct Widget {\n    public init() {}\n    public func shine() {}\n}\n"))

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.WidgetTests/testPolishes"), "\(output)")
        #expect(!output.contains("LibTests.Fixture"), "\(output)")
        #expect(!output.contains("-only-testing:LibTests/Fixture"), "\(output)")
        #expect(!output.contains("BaseCase"), "\(output)")
    }

    /// The `filtered:` line's walk from an edit to either base reaches the case that inherits it and offers neither base as a filter, since a filter naming one selects nothing.
    @Test(arguments: [
        ("Tests/LibTests/Fixture.swift", "import XCTest\n@testable import Lib\n@_spi(Testing) import GizmoKit\n\nclass Fixture: BaseCase {\n    func makeGizmo() -> Widget {\n        let widget = Widget()\n        return widget\n    }\n}\n"),
        ("Sources/GizmoKit/BaseCase.swift", "import XCTest\n\nopen class BaseCase: XCTestCase {\n    open func polish() {\n        _ = 1\n    }\n}\n"),
    ])
    func anEditedBaseReachesTheCaseAndOffersNoTestlessBase(path: String, source: String) async throws {
        let engine = try await Self.engine(editing: (path, source))

        let reached = try #require(try await engine.suitesReachingWorkingTree()).suites.map(\.filter)

        #expect(reached.contains("LibTests.WidgetTests"), "\(reached)")
        #expect(!reached.contains { $0.contains("Fixture") || $0.contains("BaseCase") }, "\(reached)")
    }

    /// A case reaching `XCTestCase` through a same-named base in its own module is no suite where only another module's base of that name declares tests, in its body or in an extension: a filter naming it would run nothing.
    @Test(arguments: [
        "import XCTest\n\nclass BaseCase: XCTestCase {\n    func testOne() {}\n}\n",
        "import XCTest\n\nclass BaseCase: XCTestCase {}\n\nextension BaseCase {\n    func testOne() {}\n}\n",
    ])
    func anotherModulesSameNamedBaseLendsTheCaseNoTests(alphaBase: String) throws {
        let (store, root) = try Self.store([
            ("Tests/AlphaTests/BaseCase.swift", alphaBase),
            ("Tests/BetaTests/BaseCase.swift", "import XCTest\n\nclass BaseCase: XCTestCase {\n    func shine() {}\n}\n"),
            ("Tests/BetaTests/GadgetTests.swift", "import XCTest\n\nfinal class GadgetTests: BaseCase {\n    func polish() {}\n}\n"),
        ])

        let inventory = try TestInventory.read(store: store, repositoryRoot: root)

        #expect(inventory.tests.map { "\($0.target)/\($0.suite)/\($0.function)" } == ["AlphaTests/BaseCase/testOne()"])
        #expect(try Self.test(at: 4, in: "Tests/BetaTests/GadgetTests.swift", store: store) == nil)
    }

    /// A `@Test` marker in a file importing no testing library is some other attribute's, so the function is no test, even inside a class.
    @Test
    func aTestMarkerInAFileImportingNoTestingLibraryIsNoTest() throws {
        let (store, root) = try Self.store([("Tests/LibTests/Gadget.swift", "final class Gadget {\n    @Test func spins() {}\n}\n")])

        let inventory = try TestInventory.read(store: store, repositoryRoot: root)

        #expect(inventory.tests.isEmpty, "\(inventory.tests.map(\.function))")
        #expect(try Self.test(at: 2, in: "Tests/LibTests/Gadget.swift", store: store) == nil)
    }

    /// A digest of the case's own file, which imports no testing library, is read as a suite's: it names the last test.
    @Test
    func aDigestOfTheCasesFileNamesItsLastTest() throws {
        // Long enough that the digest is served rather than the source.
        let tests = (0 ..< 8).map { index in
            "    func testPolishes\(index)() {\n        var total = 0\n        for step in 0 ..< 6 {\n            total += step\n        }\n        polish()\n        XCTAssertEqual(total, 15)\n    }"
        }.joined(separator: "\n\n")
        let leaf = "@_spi(Testing) import GizmoKit\n\nfinal class WidgetTests: Fixture {\n\(tests)\n\n    func testOne() {\n        shine()\n    }\n}\n"
        let (store, root) = try Self.store(Self.chain.dropLast() + [("Tests/LibTests/WidgetTests.swift", leaf)])
        let renderer = try DigestRenderer(store: store, moduleNames: store.moduleNames(), repoRoot: root)

        let output = try renderer.render(target: "Tests/LibTests/WidgetTests.swift", options: DigestOptions())

        #expect(output.contains("last test in WidgetTests: testOne()"), "\(output)")
    }

    /// A package built without its tests, whose case inherits a `GizmoKit` base through a test-target base and imports no testing library: its file is a test file the build left out, so a change it calls is still traced to its test.
    @Test
    func aCaseFileImportingNoTestingLibraryIsAnUnbuiltTestFile() async throws {
        let root = try TestSources.makeTempRepo()
        let files = [
            "Package.swift": """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Lib",
                targets: [
                    .target(name: "Lib"),
                    .target(name: "GizmoKit"),
                    .testTarget(name: "LibTests", dependencies: ["Lib", "GizmoKit"]),
                ]
            )
            """,
            "Sources/Lib/Core.swift": "public struct Widget {\n    public init() {}\n\n    public func spin() -> Int {\n        1\n    }\n}\n",
            "Sources/GizmoKit/BaseCase.swift": "import XCTest\n\nopen class BaseCase: XCTestCase {}\n",
            "Tests/LibTests/Fixture.swift": "import XCTest\nimport GizmoKit\n\nclass Fixture: BaseCase {}\n",
            "Tests/LibTests/WidgetTests.swift": "import GizmoKit\nimport Lib\n\nfinal class WidgetTests: Fixture {\n    func testOne() {\n        _ = Widget().spin()\n    }\n}\n",
        ]
        for (file, source) in files {
            try TestSources.write(source, to: file, in: root)
        }
        try TestSources.commitAll(in: root, message: "seed")
        try TestSources.write("public struct Widget {\n    public init() {}\n\n    public func spin() -> Int {\n        2\n    }\n}\n", to: "Sources/Lib/Core.swift", in: root)
        try TestSources.commitAll(in: root, message: "change")
        try await TestSources.swiftBuildSuspending(packageAt: root)
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        engine.callerDirectory = engine.repoRoot.path
        try await engine.awaitSemanticStore()

        let output = try await engine.affected(options: AffectedOptions(range: AffectedOptions.CommitRange(from: "HEAD~1", to: "HEAD")), freshness: engine.ensureFresh())

        #expect(output.contains("2 test files have no unit"), "\(output)")
        #expect(output.contains("LibTests.WidgetTests/testOne"), "\(output)")
    }
}
