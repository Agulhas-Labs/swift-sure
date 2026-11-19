//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers which owner-qualified sites of a too-common member count as reach when a file declares a type of the owner's name itself.
@Suite(.serialized, .temporaryDirectories)
struct AffectedShadowedOwnerTests {
    private static var manifest: String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Lib",
            targets: [
                .target(name: "Lib"),
                .testTarget(name: "LibTests", dependencies: ["Lib"]),
            ]
        )
        """
    }

    private static var gizmoLine: String {
        "public static func line(count: Int) -> String {\n        _ = Widget()\n        return String(count)\n    }"
    }

    private static func test(_ name: String, declaring declaration: String = "", calling expression: String) -> String {
        "import Testing\n@testable import Lib\n\n\(declaration)struct \(name) {\n    @Test func runs() {\n        _ = \(expression)\n    }\n}\n"
    }

    /// The call-site walk's answer over a fixture where `Gizmo.line` builds a `Widget` that is then changed, `line` is written in more files than a name may be and still count, `depth` hops are followed, and `extra` adds what the case needs.
    private static func affected(gizmo: String = gizmoLine, depth: Int = AffectedOptions.defaultDepth, extra: [String: String]) async throws -> String {
        let root = try TestSources.makeTempRepo()
        var files = [
            "Package.swift": manifest,
            "Sources/Lib/Core.swift": "public struct Widget {\n    public init() {}\n}\n",
            "Sources/Lib/Gizmo.swift": "public enum Gizmo {\n    \(gizmo)\n}\n",
        ]
        for index in 0 ... AffectedRenderer.nameEvidenceFileCap {
            files["Sources/Lib/Crowd\(index).swift"] = "public struct Pump\(index) {\n    public init() {}\n    public func line(count: Int) -> Int {\n        count\n    }\n}\n\npublic func crowd\(index)() -> Int {\n    Pump\(index)().line(count: \(index))\n}\n"
        }
        files.merge(extra) { $1 }
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("public struct Widget: Sendable {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        let engine = try SiftEngine(directory: root)
        return try await engine.affected(options: AffectedOptions(depth: depth), freshness: engine.ensureFresh())
    }

    /// A test file's own `private enum Gizmo` is the type its `Gizmo.line` names, not the changed one.
    @Test
    func aFileDeclaringItsOwnOwnerIsNotReached() async throws {
        let output = try await Self.affected(extra: [
            "Tests/LibTests/KettleTests.swift": Self.test("KettleTests", calling: "Gizmo.line(count: 2)"),
            "Tests/LibTests/LampTests.swift": Self.test(
                "LampTests",
                declaring: "private enum Gizmo {\n    static func line(count: Int) -> Int { count }\n}\n\n",
                calling: "Gizmo.line(count: 1)"
            ),
        ])

        #expect(output.contains("LibTests.KettleTests/runs() — 2 hops, name match"), "\(output)")
        #expect(!output.contains("LampTests"), "\(output)")
    }

    /// A nested or local `Gizmo` and a typealias to the real one leave the file's own `Gizmo.line` meaning the real type, so the file is still reached.
    @Test(arguments: [
        "private struct Helper {\n    enum Gizmo {}\n}\n\n",
        "func unrelated() {\n    struct Gizmo {}\n}\n\n",
        "private typealias Gizmo = Lib.Gizmo\n\n",
    ])
    func aNestedLocalOrAliasedGizmoShadowsNothing(declaration: String) async throws {
        let output = try await Self.affected(extra: [
            "Tests/LibTests/LampTests.swift": Self.test("LampTests", declaring: declaration, calling: "Gizmo.line(count: 1)"),
        ])

        #expect(output.contains("LibTests.LampTests/runs() — 2 hops, name match"), "\(output)")
    }

    /// A type of another name declared in the file shadows nothing.
    @Test
    func aFileDeclaringAnUnrelatedTypeIsStillReached() async throws {
        let output = try await Self.affected(extra: [
            "Tests/LibTests/LampTests.swift": Self.test("LampTests", declaring: "private enum Widget {}\n\n", calling: "Gizmo.line(count: 1)"),
        ])

        #expect(output.contains("LibTests.LampTests/runs() — 2 hops, name match"), "\(output)")
    }

    /// The real owner's own file calls its member unqualified by a module and is still reached through it.
    @Test
    func theOwnersOwnFileIsStillReached() async throws {
        let output = try await Self.affected(
            gizmo: Self.gizmoLine + "\n    public static func render() -> String {\n        Gizmo.line(count: 3)\n    }",
            depth: 3,
            extra: ["Tests/LibTests/LampTests.swift": Self.test("LampTests", calling: "Gizmo.render()")]
        )

        #expect(output.contains("LibTests.LampTests/runs() — 3 hops, name match"), "\(output)")
    }

    /// A member declared in an extension still reaches the file declaring the type it extends.
    @Test
    func anExtendedOwnersDeclarationFileIsStillReached() async throws {
        let output = try await Self.affected(
            gizmo: "public static func render() -> String {\n        Gizmo.line(count: 3)\n    }",
            depth: 3,
            extra: [
                "Sources/Lib/Gizmo+Line.swift": "extension Gizmo {\n    \(Self.gizmoLine)\n}\n",
                "Tests/LibTests/LampTests.swift": Self.test("LampTests", calling: "Gizmo.render()"),
            ]
        )

        #expect(output.contains("LibTests.LampTests/runs() — 3 hops, name match"), "\(output)")
    }

    /// `Lib.Gizmo.line` names the module's type even in a file declaring a `Gizmo` of its own.
    @Test
    func aModuleQualifiedOwnerBesideAShadowIsStillReached() async throws {
        let output = try await Self.affected(extra: [
            "Tests/LibTests/LampTests.swift": Self.test(
                "LampTests",
                declaring: "private enum Gizmo {\n    static func line(count: Int) -> Int { count }\n}\n\n",
                calling: "Lib.Gizmo.line(count: 1)"
            ),
        ])

        #expect(output.contains("LibTests.LampTests/runs() — 2 hops, name match"), "\(output)")
    }
}
