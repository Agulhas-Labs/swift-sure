//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers an implied `.init` that is a member's whole body where the member takes its result builder from a protocol requirement, with no index store: listed under the types the builder takes, out of every total, or counted as not read.
@Suite(.temporaryDirectories)
struct WhereProtocolRequirementBuilderTests {
    private static let implied = "." + "init"

    private static var types: String {
        """
        struct Gizmo { init(_ name: String) {} }
        struct Crate { init(_ name: String) {} }
        """
    }

    private static var builder: String {
        """
        @resultBuilder enum Build {
            static func buildExpression(_ g: Gizmo) -> Crate { Crate("") }
            static func buildBlock(_ c: Crate) -> Crate { c }
        }
        """
    }

    private static func lookup(_ query: String, files: [String: String]) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(types, to: "Sources/App/Types.swift", in: root)
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        let engine = try SiftEngine(directory: root)
        let freshness = try await engine.ensureFresh()
        return try await engine.lookup(symbol: query, freshness: freshness)
    }

    /// The conformance is declared by an extension in another file, to a protocol inheriting the one whose requirement carries the builder.
    private static var conformingThroughAnExtension: [String: String] {
        [
            "Sources/App/Build.swift": builder,
            "Sources/App/Maker.swift": "protocol Base { @Build var body: Crate { get } }\nprotocol Maker: Base {}",
            "Sources/App/Widget.swift": "struct Widget {\n    var body: Crate { \(implied)(\"w\") }\n}",
            "Sources/App/Conformance.swift": "extension Widget: Maker {}",
        ]
    }

    @Test
    func aBodyARequirementsBuilderBuildsIsListedUnderTheTypeItsExpressionTakes() async throws {
        let output = try await Self.lookup("Gizmo.init", files: Self.conformingThroughAnExtension)

        #expect(output.contains("an implicit .init is called once in a body Build builds, a result builder taken from a protocol requirement, any of which may be Gizmo's; not counted above, verify before deleting:"), "\(output)")
        #expect(output.contains("  Sources/App/Widget.swift:\n    :2  in Widget.body"), "\(output)")
        #expect(output.contains("no call spelled \"Gizmo.init\" anywhere in the working tree"), "\(output)")
    }

    @Test
    func aBodyARequirementsBuilderBuildsIsNoSiteOfTheTypeItStates() async throws {
        let output = try await Self.lookup("Crate.init", files: Self.conformingThroughAnExtension)

        #expect(output.contains("\"Crate.init\" (1 call site by written name in 1 file):"), "\(output)")
        #expect(!output.contains("in Widget.body"), "\(output)")
    }

    @Test
    func anotherQuerysTotalBesideABuiltBodyIsUnchanged() async throws {
        var files = Self.conformingThroughAnExtension
        files["Sources/App/Calls.swift"] = "let made = Gizmo(\"a\")"
        let output = try await Self.lookup("Gizmo.init", files: files)

        #expect(output.contains("\"Gizmo.init\" (1 call site by written name in 1 file):"), "\(output)")
        #expect(output.contains("may be Gizmo's; not counted above"), "\(output)")
    }

    @Test
    func aBuilderTheRepositoryDoesNotDeclareIsCountedAsNotRead() async throws {
        let output = try await Self.lookup("Crate.init", files: [
            "Sources/App/Maker.swift": "protocol Maker { @Outside var body: Crate { get } }",
            "Sources/App/Widget.swift": "struct Widget: Maker {\n    var body: Crate { \(Self.implied)(\"w\") }\n}",
        ])

        #expect(output.contains("1 body takes a result builder from a protocol requirement; implied .init in it is not read without a store"), "\(output)")
        #expect(!output.contains("in Widget.body"), "\(output)")
    }

    @Test
    func aBuilderTakingOnlyAGenericTypeIsCountedAsNotRead() async throws {
        let output = try await Self.lookup("Gizmo.init", files: [
            "Sources/App/Build.swift": "@resultBuilder enum Build {\n    static func buildExpression<T>(_ t: T) -> Crate { Crate(\"\") }\n    static func buildBlock(_ c: Crate) -> Crate { c }\n}",
            "Sources/App/Maker.swift": "protocol Maker { @Build var body: Crate { get } }",
            "Sources/App/Widget.swift": "struct Widget: Maker {\n    var body: Crate { \(Self.implied)(\"w\") }\n}",
        ])

        #expect(output.contains("1 body takes a result builder from a protocol requirement; implied .init in it is not read without a store"), "\(output)")
        #expect(!output.contains("in Widget.body"), "\(output)")
    }

    @Test
    func aBuilderWithNoExpressionTakesItsBlocksType() async throws {
        let output = try await Self.lookup("Gizmo.init", files: [
            "Sources/App/Build.swift": "@resultBuilder enum Build {\n    static func buildBlock(_ g: Gizmo...) -> Crate { Crate(\"\") }\n}",
            "Sources/App/Maker.swift": "protocol Maker { @Build func make() -> Crate }",
            "Sources/App/Widget.swift": "struct Widget: Maker {\n    func make() -> Crate { \(Self.implied)(\"w\") }\n}",
        ])

        #expect(output.contains("an implicit .init is called once in a body Build builds"), "\(output)")
        #expect(output.contains("    :2  in Widget.make()"), "\(output)")
    }

    @Test
    func aDeclarationCarryingItsOwnBuilderIsUnchanged() async throws {
        let output = try await Self.lookup("Gizmo.init", files: [
            "Sources/App/Build.swift": Self.builder,
            "Sources/App/Maker.swift": "protocol Maker { @Build var body: Crate { get } }",
            "Sources/App/Widget.swift": "struct Widget: Maker {\n    @Build var body: Crate { \(Self.implied)(\"w\") }\n}",
        ])

        #expect(output.contains("but an implicit .init is called once with those labels on a type the scan cannot tell, any of which may be Gizmo's; verify before deleting:"), "\(output)")
        #expect(!output.contains("a result builder taken from a protocol requirement"), "\(output)")
    }

    @Test
    func aMemberNoRequirementBuildsStaysTheStatedTypesSite() async throws {
        let output = try await Self.lookup("Crate.init", files: [
            "Sources/App/Build.swift": Self.builder,
            "Sources/App/Maker.swift": "protocol Maker { @Build var body: Crate { get } }",
            "Sources/App/Widget.swift": "struct Widget: Maker {\n    var plain: Crate { \(Self.implied)(\"w\") }\n}",
        ])

        #expect(output.contains("  Sources/App/Widget.swift:\n    :2  in Widget.plain"), "\(output)")
        #expect(!output.contains("a result builder taken from a protocol requirement"), "\(output)")
        #expect(!output.contains("not read without a store"), "\(output)")
    }
}
