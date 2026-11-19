//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers a changed member whose own name is too common to count: the walk takes its owner from the member's declaration, so the first hop already follows it where that owner qualifies it.
@Suite(.serialized, .temporaryDirectories)
struct AffectedChangedCommonMemberTests {
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

    private static func test(_ name: String, calling expression: String) -> String {
        "import Testing\n@testable import Lib\n\nstruct \(name) {\n    @Test func runs() {\n        _ = \(expression)\n    }\n}\n"
    }

    private static func gizmo(returning value: String) -> String {
        "public enum Gizmo {\n    public static func line(count: Int) -> String {\n        String(\(value))\n    }\n}\n"
    }

    /// An engine over a fixture where `Gizmo.line` itself is changed and uncommitted, with no build, `line` written in more files than a name may be and still count, one suite calling `Gizmo.line` and one calling another type's `line`; when asked to, `Gizmo` itself is also written in more files than a name may be, so only the written `Gizmo.line` can reach the suite.
    private static func engine(crowdingOwner: Bool = false) async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        var files = [
            "Package.swift": manifest,
            "Sources/Lib/Gizmo.swift": gizmo(returning: "count"),
            "Tests/LibTests/KettleTests.swift": test("KettleTests", calling: "Gizmo.line(count: 2)"),
            "Tests/LibTests/LampTests.swift": test("LampTests", calling: "Pump0().line(count: 2)"),
        ]
        for index in 0 ... AffectedRenderer.nameEvidenceFileCap {
            files["Sources/Lib/Crowd\(index).swift"] = "public struct Pump\(index) {\n    public init() {}\n    public func line(count: Int) -> Int {\n        count\n    }\n}\n\npublic func crowd\(index)() -> Int {\n    \(crowdingOwner ? "_ = Gizmo.self\n    " : "")Pump\(index)().line(count: \(index))\n}\n"
        }
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write(gizmo(returning: "count + 1"), to: "Sources/Lib/Gizmo.swift", in: root)
        return try SiftEngine(directory: root)
    }

    /// The call-site walk `affected` falls back to with no store reaches the suite calling `Gizmo.line` on the first hop, names `line` as followed only where its type qualifies it, and not as dropped.
    @Test
    func theCallSiteWalkFollowsAChangedTooCommonMemberThroughItsOwnerOnTheFirstHop() async throws {
        let engine = try await Self.engine()

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.KettleTests/runs() — 1 hop, name match"), "\(output)")
        #expect(!output.contains("LampTests"), "\(output)")
        #expect(output.contains("followed only where its type qualifies it (Gizmo.line)"), "\(output)")
        #expect(!output.contains("dropped rather than admitted"), "\(output)")
    }

    /// The written-name walk behind the `filtered:` line reaches the same suite on the first hop, and not the one calling another type's `line`.
    @Test
    func theWrittenNameWalkFollowsAChangedTooCommonMemberThroughItsOwnerOnTheFirstHop() async throws {
        let engine = try await Self.engine(crowdingOwner: true)
        _ = try await engine.ensureFresh()

        let reached = try #require(try await engine.suitesReachingWorkingTree()).suites

        #expect(reached.contains { $0.filter == "LibTests.KettleTests" && $0.depth == 1 }, "\(reached)")
        #expect(!reached.contains { $0.filter.contains("LampTests") }, "\(reached)")
    }
}
