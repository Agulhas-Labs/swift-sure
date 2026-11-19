//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers a route through a member whose name is too common to count on its own: the walk still follows it where it is written qualified by its owner, `Gizmo.line(count:)`, and nowhere else.
@Suite(.serialized, .temporaryDirectories)
struct AffectedCommonMemberRouteTests {
    private static func manifest() -> String {
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

    /// `Gizmo.line(count:)` builds a `Widget`, so it is one hop from a change to `Widget`, and `line` is written in more files than a name may be and still count.
    private static var files: [String: String] {
        var files = [
            "Sources/Lib/Core.swift": "public struct Widget {\n    public init() {}\n}\n",
            "Sources/Lib/Gizmo.swift": "public enum Gizmo {\n    public static func line(count: Int) -> String {\n        _ = Widget()\n        return String(count)\n    }\n}\n",
            "Tests/LibTests/KettleTests.swift": "import Testing\n@testable import Lib\n\nstruct KettleTests {\n    @Test func boils() {\n        #expect(Gizmo.line(count: 2) == \"2\")\n    }\n}\n",
            "Tests/LibTests/LampTests.swift": "import Testing\n@testable import Lib\n\nstruct LampTests {\n    @Test func lights() {\n        #expect(Pump0().line(count: 2) == 2)\n    }\n}\n",
        ]
        for index in 0 ... AffectedRenderer.nameEvidenceFileCap {
            files["Sources/Lib/Crowd\(index).swift"] = "public struct Pump\(index) {\n    public init() {}\n    public func line(count: Int) -> Int {\n        count\n    }\n}\n\npublic func crowd\(index)() -> Int {\n    Pump\(index)().line(count: \(index))\n}\n"
        }
        return files
    }

    /// An engine over the fixture with `Widget` changed and uncommitted, and no build, so every walk is by written name.
    private static func engine() async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(manifest(), to: "Package.swift", in: root)
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("public struct Widget: Sendable {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        return try SiftEngine(directory: root)
    }

    /// The line a filtered run adds walks every token spelling a name: the suite calling `Gizmo.line` is reached, the one writing only another type's `line` is not.
    @Test
    func theWrittenNameWalkFollowsATooCommonMemberWhereItsOwnerQualifiesIt() async throws {
        let engine = try await Self.engine()
        _ = try await engine.ensureFresh()

        let reached = try #require(try await engine.suitesReachingWorkingTree()).suites

        #expect(reached.contains { $0.filter == "LibTests.KettleTests" && $0.depth == 2 }, "\(reached)")
        #expect(!reached.contains { $0.filter.contains("LampTests") }, "\(reached)")
    }

    /// The call-site walk `affected` falls back to with no store: the same route, and `line` is not named as dropped, since its qualified sites were followed.
    @Test
    func theCallSiteWalkFollowsATooCommonMemberWhereItsOwnerQualifiesIt() async throws {
        let engine = try await Self.engine()

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.KettleTests/boils() — 2 hops, name match"), "\(output)")
        #expect(!output.contains("LampTests"), "\(output)")
        #expect(output.contains("1 name in that scan was written in more than 40 files and followed only where its type qualifies it (Gizmo.line) — its bare, Self. and x. sites were dropped, so NOTHING is reported through them: line"), "\(output)")
        #expect(!output.contains("dropped rather than admitted"), "\(output)")
    }
}
