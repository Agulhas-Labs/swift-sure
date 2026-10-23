//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure checkup`'s `exposure` check over real changes in a temporary repository: it quotes the verdict line `swift-sure diff` prints.
@Suite(.temporaryDirectories)
struct CheckupExposureCommandTests {
    private static func manifest(product: Bool) -> String {
        let products = product ? "products: [.library(name: \"GizmoKit\", targets: [\"GizmoKit\"])],\n    " : ""
        return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            \(products)targets: [.target(name: "GizmoKit"), .target(name: "GizmoTools", dependencies: ["GizmoKit"])]
        )
        """
    }

    private static func repository(published: Bool = false) throws -> URL {
        let root = try MCPTestRepo.make()
        try MCPTestRepo.add([
            "Package.swift": manifest(product: published),
            "Sources/GizmoKit/Gizmo.swift": "struct Gizmo {}\n",
            "Sources/GizmoTools/Tool.swift": "struct Tool {}\n",
        ], to: root)
        return root
    }

    private static func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init)
    }

    private static func checkup(in root: URL, sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String] {
        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let (text, refused) = try await CheckupCommand.parse(["--root", root.path]).answer(registry: registry)
        #expect(!refused, sourceLocation: sourceLocation)
        return lines(text)
    }

    private static func diffAccess(in root: URL) async throws -> [String] {
        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let (text, _) = try await DiffCommand.parse(["--root", root.path]).answer(registry: registry)
        return lines(text).filter { $0.hasPrefix("access:") }
    }

    private static func exposed(_ lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix("exposed ") }
    }

    private static func checked(_ lines: [String]) -> String {
        lines.first { $0.hasPrefix("checked: ") } ?? ""
    }

    @Test
    func aPublicDeclarationNothingOutsideItsModuleUsesIsOneFindingQuotingDiffsLine() async throws {
        let root = try Self.repository()
        try Self.write("struct Gizmo {}\npublic func restock() {}\n", "Sources/GizmoKit/Gizmo.swift", in: root)

        let lines = try await Self.checkup(in: root)
        let access = try await Self.diffAccess(in: root)

        #expect(access.count == 1)
        #expect(access.first?.contains("with no use outside module GizmoKit") == true)
        let found = Self.exposed(lines)
        #expect(found.count == 1)
        #expect(found.first?.contains(access.first ?? "?") == true)
        #expect(found.first?.hasSuffix(" — swift-sure diff") == true)
        #expect(Self.checked(lines).contains("exposure ("))
    }

    /// Pins that an exposure finding points to `diff` over the range the checkup was given.
    @Test
    func theExposurePointerCarriesTheRangeTheCheckupWasGiven() async throws {
        let root = try Self.repository()
        try MCPTestRepo.run(git: ["tag", "base"], in: root)
        try Self.write("struct Gizmo {}\npublic func restock() {}\n", "Sources/GizmoKit/Gizmo.swift", in: root)
        try MCPTestRepo.run(git: ["add", "-A"], in: root)
        try MCPTestRepo.run(git: ["commit", "-m", "edit"], in: root)
        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))

        let (text, refused) = try await CheckupCommand.parse(["--root", root.path, "base..HEAD"]).answer(registry: registry)

        #expect(!refused)
        let found = Self.exposed(Self.lines(text))
        #expect(found.count == 1)
        #expect(found.first?.hasSuffix(" — swift-sure diff base..HEAD") == true)
    }

    @Test
    func theDeclarationsOwnLinesNeverAppear() async throws {
        let root = try Self.repository()
        try Self.write("struct Gizmo {}\npublic func restock() {}\n", "Sources/GizmoKit/Gizmo.swift", in: root)

        let lines = try await Self.checkup(in: root)

        #expect(!lines.contains { $0.contains("GizmoKit.restock()") })
        #expect(!lines.contains { $0.contains("public → internal") })
        #expect(!lines.contains { $0.contains("uses name-matched") || $0.contains("uses resolved") })
    }

    @Test
    func everyPublicDeclarationUsedFromAnotherPackageGivesNoFinding() async throws {
        let root = try Self.repository()
        try Self.write("// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"Tools\",\n    targets: [.target(name: \"WidgetKit\")]\n)\n", "Tools/Package.swift", in: root)
        try Self.write("import GizmoKit\n\nfunc stock() {\n    restock()\n}\n", "Tools/Sources/WidgetKit/Stock.swift", in: root)
        try Self.write("struct Gizmo {}\npublic func restock() {}\n", "Sources/GizmoKit/Gizmo.swift", in: root)

        let lines = try await Self.checkup(in: root)
        let access = try await Self.diffAccess(in: root)

        #expect(access.first?.contains("each has a use that needs its level") == true)
        #expect(Self.exposed(lines).isEmpty)
        #expect(Self.checked(lines).contains("exposure"))
        #expect(!lines.contains { $0.contains("exposure (not built yet)") })
    }

    @Test
    func aRangeThatPutsNothingAtThoseLevelsGivesNoFinding() async throws {
        let root = try Self.repository()
        try Self.write("struct Gizmo {}\nfunc restock() {}\n", "Sources/GizmoKit/Gizmo.swift", in: root)

        let lines = try await Self.checkup(in: root)

        #expect(Self.exposed(lines).isEmpty)
        #expect(Self.checked(lines).contains("exposure"))
        #expect(!lines.contains { $0.hasPrefix("not checked:") && $0.contains("exposure") })
    }

    @Test
    func aPublishedLibrarysPublicDeclarationCarriesTheQuestionLine() async throws {
        let root = try Self.repository(published: true)
        try Self.write("struct Gizmo {}\npublic func restock() {}\n", "Sources/GizmoKit/Gizmo.swift", in: root)

        let found = try await Self.exposed(Self.checkup(in: root))

        #expect(found.count == 2)
        #expect(found.contains { $0.contains("GizmoKit is a library product this repository publishes: its public API may serve consumers this repository does not contain") })
    }
}
