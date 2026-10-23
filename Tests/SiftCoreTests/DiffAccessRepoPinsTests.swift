//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section over a whole repository with no index store: witnesses by name, test files read for `@testable`, the packages a use comes from, the lookup budget and a range with nothing at the judged levels.
///
/// Each test commits a package, edits the working tree and reads the diff of the working tree, so every use is name-matched.
@Suite(.temporaryDirectories)
struct DiffAccessRepoPinsTests {
    /// A conformance to a protocol this repository declares keeps the member named like its requirement out of every count, without a store.
    @Test func aWitnessIsNeverListedWithoutAStoreByName() async throws {
        let root = try Self.depot()
        try TestSources.write("public protocol Stocking {\n    func restock()\n}\n", to: "Sources/GizmoKit/Stocking.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("public struct Shelf: Stocking {\n    public func restock() {}\n}\n", to: "Sources/GizmoKit/Shelf.swift", in: root)

        let section = try await Self.section(of: DiffEngineTests.diff(root))

        #expect(section == [
            "access: this range put 1 declaration at public, 1 with no use outside module GizmoKit",
            "  uses name-matched over the working tree, which can miss a use through a typealias, a closure or a macro",
            "  + GizmoKit.Shelf  Sources/GizmoKit/Shelf.swift:1  public → internal: no use by that name outside module GizmoKit",
            "  not judged: 1 protocol witness",
        ])
    }

    /// The answer re-reads a using test file's imports: one importing the module `@testable` is no production use, so the declaration suggests `internal` and says why.
    @Test func aDeclarationUsedOnlyFromTestableTestsSuggestsInternal() async throws {
        let root = try Self.depot(testTarget: true)
        try Self.commitBase(in: root)
        try TestSources.write("struct Gizmo {}\npublic func restock() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.write("@testable import GizmoKit\nimport Testing\n\n@Test func stock() {\n    restock()\n}\n", to: "Tests/GizmoTests/GizmoTests.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("access: this range put 1 declaration at public, 1 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:2  public → internal: used only from tests, which import it @testable"), "\(answer)")
    }

    /// A test file in the same package that imports the module plainly is a use from its package like any other, so it allows `package`.
    @Test func aPlainTestImportFromTheSamePackageAllowsPackage() async throws {
        let root = try Self.depot(testTarget: true)
        try Self.commitBase(in: root)
        try TestSources.write("struct Gizmo {}\npublic func restock() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.write("import GizmoKit\nimport Testing\n\n@Test func stock() {\n    restock()\n}\n", to: "Tests/GizmoTests/GizmoTests.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("access: this range put 1 declaration at public, 1 used only inside its package"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:2  public → package: used only from GizmoTests, in this package"), "\(answer)")
    }

    /// A test file in another package that imports the module plainly needs the declaration's level: `package` would not reach it.
    ///
    /// Every subject then needs its level, and the section is the one line saying so, then the line saying how the uses were found.
    @Test func aPlainTestImportFromAnotherPackageNeedsTheLevel() async throws {
        let root = try Self.depot()
        try Self.writeOtherPackage(in: root, target: ".testTarget(name: \"WidgetTests\")")
        try Self.commitBase(in: root)
        try TestSources.write("struct Gizmo {}\npublic func restock() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.write("import GizmoKit\nimport Testing\n\n@Test func stock() {\n    restock()\n}\n", to: "Tools/Tests/WidgetTests/WidgetTests.swift", in: root)

        let section = try await Self.section(of: DiffEngineTests.diff(root))

        #expect(section == [
            "access: this range put 1 declaration at public; each has a use that needs its level",
            "  uses name-matched over the working tree, which can miss a use through a typealias, a closure or a macro",
        ])
    }

    /// A production use from a module of another `Package.swift` needs `public`: no `package` suggestion, and no line.
    @Test func aUserInAnotherPackageNeedsPublic() async throws {
        let root = try Self.depot()
        try Self.writeOtherPackage(in: root, target: ".target(name: \"WidgetKit\")")
        try Self.commitBase(in: root)
        try TestSources.write("struct Gizmo {}\npublic func restock() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.write("import GizmoKit\n\nfunc stock() {\n    restock()\n}\n", to: "Tools/Sources/WidgetKit/Stock.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("access: this range put 1 declaration at public; each has a use that needs its level"), "\(answer)")
        #expect(!answer.contains("GizmoKit.restock()"), "\(answer)")
    }

    /// A use from an app project's target of a local package's declaration needs `public`: an Xcode project gets no `package` suggestion.
    @Test func anAppProjectsUseOfALocalPackagesDeclarationNeedsPublic() async throws {
        let root = try Self.depot()
        try TestSources.write(
            """
            name: GizmoApp
            targets:
              GizmoApp:
                type: application
                sources:
                  - path: App
            """,
            to: "project.yml",
            in: root
        )
        try TestSources.write("import GizmoKit\n\nfunc launch() {}\n", to: "App/Launch.swift", in: root)
        try Self.commitBase(in: root)
        try TestSources.write("struct Gizmo {}\npublic func restock() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.write("import GizmoKit\n\nfunc launch() {\n    restock()\n}\n", to: "App/Launch.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("access: this range put 1 declaration at public; each has a use that needs its level"), "\(answer)")
        #expect(!answer.contains("GizmoKit.restock()"), "\(answer)")
    }

    /// Declarations are looked up in the order the declarations section lists them, by line and not by name, so the fifty-first it lists is the one `not checked` and in no count; the fifty looked up are counted, ten listed, the rest named on one line.
    @Test func theFiftyFirstLookupIsNotChecked() async throws {
        let root = try Self.depot()
        try Self.commitBase(in: root)
        let functions = (1 ... AccessLookup.lookupCap + 1).map { "public func step\($0)() {}" }
        try TestSources.write("struct Gizmo {}\n" + functions.joined(separator: "\n") + "\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("access: this range put 50 declarations at public, 50 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  not checked: 1 more (over the first 50)"), "\(answer)")
        #expect(answer.contains("  +40 more: GizmoKit.step11(), "), "\(answer)")
        #expect(answer.contains("GizmoKit.step50()"), "\(answer)")
        #expect(!answer.contains("GizmoKit.step51()"), "\(answer)")
    }

    /// A range that adds only internal declarations and edits a public one's body puts nothing at the judged levels, so the answer has no access section at all.
    @Test func aRangePuttingNothingAtTheJudgedLevelsPrintsNoSection() async throws {
        let root = try Self.depot()
        try TestSources.write("public func restock() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("public func restock() {\n    shelve()\n}\n\nfunc shelve() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("shelve()"), "\(answer)")
        #expect(!answer.contains("access:"), "\(answer)")
    }

    /// A witness check is a lookup like any other, so a witness among the first fifty spends a place in the budget: forty-nine declarations are judged, one is not judged and the fifty-first is `not checked`.
    @Test func aWitnessCheckSpendsALookup() async throws {
        let root = try Self.depot()
        try TestSources.write("public protocol Stocking {\n    func restock()\n}\n", to: "Sources/GizmoKit/Stocking.swift", in: root)
        try Self.commitBase(in: root)
        let functions = (1 ... AccessLookup.lookupCap - 1).map { "public func step\($0)() {}" }
        try TestSources.write("public struct Shelf: Stocking {\n    public func restock() {}\n}\n" + functions.joined(separator: "\n") + "\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("access: this range put 49 declarations at public, 49 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  not judged: 1 protocol witness"), "\(answer)")
        #expect(answer.contains("  not checked: 1 more (over the first 50)"), "\(answer)")
        #expect(!answer.contains("GizmoKit.step49()"), "\(answer)")
    }
}

extension DiffAccessRepoPinsTests {
    /// The access section's lines: its verdict line and the indented lines after it.
    static func section(of answer: String) -> [String] {
        let lines = answer.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("access:") }) else { return [] }
        return [lines[start]] + lines[(start + 1)...].prefix { $0.hasPrefix("  ") }
    }

    /// A fresh repository holding the `Depot` package: `GizmoKit` and `GizmoTools`, which depends on it, and a `GizmoTests` test target when asked.
    static func depot(testTarget: Bool = false) throws -> URL {
        let root = try TestSources.makeTempRepo()
        let tests = testTarget ? ", .testTarget(name: \"GizmoTests\", dependencies: [\"GizmoKit\"])" : ""
        try TestSources.write("""
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [.target(name: "GizmoKit"), .target(name: "GizmoTools", dependencies: ["GizmoKit"])\(tests)]
        )
        """, to: "Package.swift", in: root)
        return root
    }

    /// Commits the module's starting file, so the edit after it is the range.
    static func commitBase(in root: URL) throws {
        try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
    }

    /// A second package under `Tools/`, holding the one target `target` declares.
    static func writeOtherPackage(in root: URL, target: String) throws {
        try TestSources.write("""
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Tools",
            targets: [\(target)]
        )
        """, to: "Tools/Package.swift", in: root)
    }
}
