//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers what the call-site walk says and reaches for a too-common member followed only where its owner qualifies it: the note naming it, and which spellings of the owner count.
@Suite(.serialized, .temporaryDirectories)
struct AffectedOwnerQualifiedNoteTests {
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

    private static func test(_ name: String, calling expression: String) -> String {
        "import Testing\n@testable import Lib\n\nstruct \(name) {\n    @Test func runs() {\n        _ = \(expression)\n    }\n}\n"
    }

    /// The call-site walk's answer over a fixture where `Gizmo.line` builds a `Widget` that is then changed, `line` is written in more files than a name may be and still count, and `extra` adds what the case needs.
    private static func affected(gizmo: String = gizmoLine, extra: [String: String]) async throws -> String {
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
        return try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())
    }

    /// A caller writing `line` bare, inside a sibling of the owner, is dropped, and the answer says the name was followed only where qualified.
    @Test
    func aBareOnlyCallerIsNamedInTheNoteWhileTheQualifiedCallerIsReached() async throws {
        let output = try await Self.affected(extra: [
            "Tests/LibTests/KettleTests.swift": Self.test("KettleTests", calling: "Gizmo.line(count: 2)"),
            "Sources/Lib/Sibling.swift": "public enum Sibling {\n    public static func render() {\n        line(count: 1)\n    }\n}\n",
            "Tests/LibTests/LampTests.swift": Self.test("LampTests", calling: "Sibling.render()"),
        ])

        #expect(output.contains("LibTests.KettleTests/runs() — 2 hops, name match"), "\(output)")
        #expect(!output.contains("LampTests"), "\(output)")
        #expect(output.contains("followed only where its type qualifies it (Gizmo.line) — its bare, Self. and x. sites were dropped, so NOTHING is reported through them: line"), "\(output)")
    }

    /// A specialized owner, `Box<Int>.line`, is the same spelling as `Box.line` once the generic arguments are read past.
    @Test
    func aGenericOwnerIsReached() async throws {
        let output = try await Self.affected(
            gizmo: Self.gizmoLine + "\n}\n\npublic enum Box<Element> {\n    public static func line(count: Int) -> Int {\n        _ = Widget()\n        return count\n    }",
            extra: ["Tests/LibTests/KettleTests.swift": Self.test("KettleTests", calling: "Box<Int>.line(count: 2)")]
        )

        #expect(output.contains("LibTests.KettleTests/runs() — 2 hops, name match"), "\(output)")
    }

    /// A module-qualified owner, `Lib.Gizmo.line`, reads as its last owner component.
    @Test
    func aModuleQualifiedOwnerIsReached() async throws {
        let output = try await Self.affected(extra: ["Tests/LibTests/KettleTests.swift": Self.test("KettleTests", calling: "Lib.Gizmo.line(count: 2)")])

        #expect(output.contains("LibTests.KettleTests/runs() — 2 hops, name match"), "\(output)")
    }

    /// `Self.line` in another type's own body is not a spelling the walk can tell from that type's member.
    @Test
    func selfQualifiedSitesAreNotAdmitted() async throws {
        let output = try await Self.affected(extra: [
            "Tests/LibTests/KettleTests.swift": Self.test("KettleTests", calling: "Gizmo.line(count: 2)"),
            "Sources/Lib/Gadget.swift": "public struct Gadget {\n    public static func line(count: Int) -> Int { count }\n    public static func build() -> Int {\n        Self.line(count: 1)\n    }\n}\n",
            "Tests/LibTests/LampTests.swift": Self.test("LampTests", calling: "Gadget.build()"),
        ])

        #expect(output.contains("LibTests.KettleTests/runs() — 2 hops, name match"), "\(output)")
        #expect(!output.contains("LampTests"), "\(output)")
    }

    /// The owner's spelling inside a string literal or a comment is no call.
    @Test
    func aMentionInAStringOrACommentIsNotAdmitted() async throws {
        let output = try await Self.affected(extra: [
            "Tests/LibTests/KettleTests.swift": Self.test("KettleTests", calling: "Gizmo.line(count: 2)"),
            "Tests/LibTests/LampTests.swift": "import Testing\n@testable import Lib\n\nstruct LampTests {\n    // Gizmo.line(count: 3) is not called here\n    @Test func prints() {\n        _ = \"Gizmo.line(count: 4)\"\n    }\n}\n",
        ])

        #expect(output.contains("LibTests.KettleTests/runs() — 2 hops, name match"), "\(output)")
        #expect(!output.contains("LampTests"), "\(output)")
    }
}
