//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A module-qualified digest target names the declaration whose whole path it spells, so every exact target an ambiguity answer prints resolves to that one declaration.
@Suite(.temporaryDirectories)
struct DigestExactTargetTests {
    private static let files: [String: String] = [
        "Sources/Core/Gizmo.swift": "public struct Gizmo {\n    var spin = 0\n}\n",
        "Sources/Core/Depot.swift": "public struct Depot {\n    public struct Gizmo {\n        var wobble = 0\n    }\n}\n",
        "Sources/Core/Crate.swift": "public struct Crate {\n    public struct Depot {\n        public struct Gizmo {\n            var lift = 0\n        }\n    }\n}\n",
    ]

    private static var manifest: String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(name: "Core", targets: [.target(name: "Core")])
        """
    }

    private static func engine() async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(manifest, to: "Package.swift", in: root)
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return engine
    }

    @Test
    func aModuleQualifiedTopLevelTypeIsNotAmbiguousWithANestedTwin() async throws {
        let answer = try await Self.engine().digest(target: "Core.Gizmo", options: DigestOptions())

        #expect(!answer.contains("is ambiguous"))
        #expect(answer.contains("Sources/Core/Gizmo.swift"))
        #expect(answer.contains("spin"))
    }

    @Test
    func aModuleQualifiedNestedTypeIsNotAmbiguousWithADeeperTwin() async throws {
        let answer = try await Self.engine().digest(target: "Core.Depot.Gizmo", options: DigestOptions())

        #expect(!answer.contains("is ambiguous"))
        #expect(answer.contains("Sources/Core/Depot.swift"))
        #expect(answer.contains("wobble"))
    }

    @Test
    func aBareNameSharedByTypesStaysAmbiguous() async throws {
        let answer = try await Self.engine().digest(target: "Gizmo", options: DigestOptions())

        #expect(answer.contains("Gizmo is ambiguous — 3 declarations"))
    }

    @Test
    func everyExactTargetAnAmbiguityAnswerPrintsServesThatOneDeclaration() async throws {
        let engine = try await Self.engine()
        let answer = try engine.digest(target: "Gizmo", options: DigestOptions())
        let lines = answer.split(separator: "\n").filter { $0.hasPrefix("  digest ") }
        #expect(lines.count == 3)

        for line in lines {
            let parts = line.dropFirst("  digest ".count).components(separatedBy: " — ")
            let target = parts[0]
            let path = parts[2].components(separatedBy: ":")[0]
            let followed = try engine.digest(target: target, options: DigestOptions())
            #expect(!followed.contains("is ambiguous"), "\(target) answered another ambiguity")
            #expect(followed.contains(path), "\(target) did not serve \(path)")
        }
    }
}
