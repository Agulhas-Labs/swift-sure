//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `where Dep.member` and `digest Dep.member` for a `Dep` declared in a sibling root: the answer counts the repository's same-named members on other types, lists none of them, and ends with the sibling's pointer.
@Suite(.temporaryDirectories)
struct WhereExternalTypeSiblingTests {
    private static var countLine: String {
        "write is declared 1 time on other types in this repository — where write lists them"
    }

    /// A repository writing a dependency's `Dep` as a parameter's type, and declaring a `write` of its own on `Box`.
    private static func localEngine(registry: RootsRegistry) async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("import Dep\n\nfunc use(_ dep: Dep) {}\n", to: "Sources/App/Use.swift", in: root)
        try TestSources.write("struct Box {\n    func write() {}\n}\n", to: "Sources/App/Box.swift", in: root)
        try TestSources.commitAll(in: root, message: "a dependency's type, unbuilt")
        let engine = try SiftEngine(directory: root, registry: registry)
        _ = try await engine.ensureFresh()
        return engine
    }

    /// A sibling root indexed under `registry` holding `files`.
    private static func indexSibling(_ files: [String: String], registry: RootsRegistry) async throws -> URL {
        let sibling = try TestSources.makeTempRepo()
        for (path, source) in files {
            try TestSources.write(source, to: path, in: sibling)
        }
        try TestSources.commitAll(in: sibling, message: "the dependency")
        _ = try await SiftEngine(directory: sibling, registry: registry).ensureFresh()
        return sibling
    }

    private static func makeRegistry() throws -> RootsRegistry {
        try RootsRegistry(fileURL: TestSources.makeTempDirectory().appendingPathComponent("roots.json"))
    }

    private static func whereOutput(_ engine: SiftEngine) async throws -> String {
        try await engine.lookup(symbol: "Dep.write", freshness: engine.ensureFresh(), options: WhereOptions(includeSemantic: false, declarationsOnly: true))
    }

    /// The same-named member on another type is counted, never listed.
    @Test
    func theSameNamedMemberOnAnotherTypeIsCountedNotListed() async throws {
        let engine = try await Self.localEngine(registry: Self.makeRegistry())
        let whereOutput = try await Self.whereOutput(engine)
        let digestOutput = try engine.digest(target: "Dep.write", options: DigestOptions())

        for output in [whereOutput, digestOutput] {
            #expect(output.contains(Self.countLine), "\(output)")
            #expect(!output.contains("other declarations of"), "\(output)")
            #expect(!output.contains("Sources/App/Box.swift"), "\(output)")
        }
    }

    /// A sibling root declaring the type draws the type's pointer on both answers.
    @Test
    func aSiblingDeclaringTheTypeIsPointedAt() async throws {
        let registry = try Self.makeRegistry()
        let sibling = try await Self.indexSibling(["Sources/Lib/Dep.swift": "public struct Dep {}\n"], registry: registry)
        let engine = try await Self.localEngine(registry: registry)
        let whereOutput = try await Self.whereOutput(engine)
        let digestOutput = try engine.digest(target: "Dep.write", options: DigestOptions())

        for output in [whereOutput, digestOutput] {
            #expect(output.contains("Dep is declared in \(sibling.path) (per that root's last index) — retry with root=\(sibling.path)"), "\(output)")
        }
    }

    /// A sibling declaring the type and the member in an extension draws the path's pointer on both answers.
    @Test
    func aSiblingDeclaringTheMemberInAnExtensionIsPointedAtByPath() async throws {
        let registry = try Self.makeRegistry()
        let sibling = try await Self.indexSibling([
            "Sources/Lib/Dep.swift": "public struct Dep {}\n",
            "Sources/Lib/Dep+Write.swift": "extension Dep {\n    static func write(_ value: Int, tool: Int) {}\n}\n",
        ], registry: registry)
        let engine = try await Self.localEngine(registry: registry)
        let whereOutput = try await Self.whereOutput(engine)
        let digestOutput = try engine.digest(target: "Dep.write", options: DigestOptions())

        for output in [whereOutput, digestOutput] {
            #expect(output.contains("Dep.write is declared in \(sibling.path) (per that root's last index) — retry with root=\(sibling.path)"), "\(output)")
        }
    }

    /// A sibling holding no `Dep` draws no pointer.
    @Test
    func aSiblingWithoutTheTypeDrawsNoPointer() async throws {
        let registry = try Self.makeRegistry()
        let sibling = try await Self.indexSibling(["Sources/Lib/Other.swift": "public struct Other { func write() {} }\n"], registry: registry)
        let engine = try await Self.localEngine(registry: registry)
        let output = try await Self.whereOutput(engine)

        #expect(!output.contains(sibling.path), "\(output)")
    }
}
