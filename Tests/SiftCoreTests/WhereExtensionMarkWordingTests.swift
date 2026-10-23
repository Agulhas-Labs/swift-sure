//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The `extends another` mark on a declarations row says `another module's` only when the extended type is in another module.
@Suite(.temporaryDirectories)
struct WhereExtensionMarkWordingTests {
    private static func answer(_ files: [String: String]) async throws -> String {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "mark wording")
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))
    }

    private static func manifest(_ targets: [String]) -> String {
        let lines = targets.map { "    .target(name: \"\($0)\", path: \"Sources/\($0)\")," }.joined(separator: "\n")
        return "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Pair\", targets: [\n\(lines)\n])\n"
    }

    /// An extension written through a typealias of a type in the same module is marked `another Gizmo`.
    @Test
    func aSameModuleExtensionIsMarkedAnother() async throws {
        let source = "class Base {}\ntypealias Gizmo = Base\nstruct Holder {\n    struct Gizmo {}\n}\n\nextension Gizmo {\n    func spin() {}\n}\n"
        let answer = try await Self.answer(["Package.swift": Self.manifest(["Alpha"]), "Sources/Alpha/Gizmo.swift": source])

        #expect(answer.contains("Sources/Alpha/Gizmo.swift:7-9 — extends another Gizmo\n"), "\(answer)")
        #expect(!answer.contains("another module's"), "\(answer)")
    }

    /// An extension in another module of a nested type is still marked `another module's Gizmo`.
    @Test
    func anOtherModuleExtensionIsMarkedAnotherModules() async throws {
        let answer = try await Self.answer([
            "Package.swift": Self.manifest(["Alpha", "Beta"]),
            "Sources/Alpha/Outer.swift": "public enum Outer {\n    public struct Gizmo {}\n}\n",
            "Sources/Beta/Gizmo.swift": "extension Gizmo {\n    func f() {}\n}\n",
        ])

        #expect(answer.contains("Sources/Beta/Gizmo.swift:1-3 — extends another module's Gizmo"), "\(answer)")
    }
}
