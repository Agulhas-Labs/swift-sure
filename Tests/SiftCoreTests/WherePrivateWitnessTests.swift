//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A `fileprivate` member of a type that conforms to a protocol may witness a requirement called through the protocol from another file, so `where` does not narrow its sites to its own file.
@Suite(.temporaryDirectories)
struct WherePrivateWitnessTests {
    private static func lookup(_ symbol: String, declaring declaration: String) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(declaration, to: "Sources/Gizmo/Fast.swift", in: root)
        try TestSources.write("func spinUp(_ s: any Spinner) -> Int { s.whirl() }\n", to: "Sources/Gizmo/Slow.swift", in: root)
        try TestSources.write("import Gizmo\nfunc dial() { _ = (nil as (any Spinner)?)?.whirl() }\n", to: "Tests/GizmoTests/DialTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)
        return try await engine.lookup(symbol: symbol, freshness: engine.ensureFresh())
    }

    @Test
    func aFileprivateWitnessKeepsTheCallsThroughItsProtocol() async throws {
        let output = try await Self.lookup(
            "Fast.whirl",
            declaring: """
            public protocol Spinner { func whirl() -> Int }
            private struct Fast: Spinner { fileprivate func whirl() -> Int { 1 } }
            """
        )

        #expect(!output.contains("narrowed to its declaring file"), "\(output)")
        #expect(output.contains(":1  in spinUp"), "\(output)")
        #expect(output.contains(":2  in dial()"), "\(output)")
    }

    @Test
    func aFileprivateWitnessDeclaredInAnExtensionKeepsThem() async throws {
        let output = try await Self.lookup(
            "Fast.whirl",
            declaring: """
            public protocol Spinner { func whirl() -> Int }
            private struct Fast {}
            extension Fast: Spinner { fileprivate func whirl() -> Int { 1 } }
            """
        )

        #expect(!output.contains("narrowed to its declaring file"), "\(output)")
        #expect(output.contains(":1  in spinUp"), "\(output)")
        #expect(output.contains(":2  in dial()"), "\(output)")
    }

    @Test
    func aFileprivateMemberInAFileWithNoInheritanceClauseIsStillNarrowed() async throws {
        let output = try await Self.lookup(
            "Fast.whirl",
            declaring: """
            private struct Fast { fileprivate func whirl() -> Int { 1 } }
            """
        )

        #expect(output.contains("narrowed to its declaring file, as it is fileprivate: 2 elsewhere dropped, 0 kept"), "\(output)")
        #expect(!output.contains("Sources/Gizmo/Slow.swift"), "\(output)")
    }
}
