//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the line that ends a type digest: it names only the synthesized members the type's declarations make possible.
@Suite(.temporaryDirectories)
struct DigestSynthesizedNoteTests {
    /// Enough members, with bodies, that the digest is served rather than the source.
    private static let padding = (1 ... 24).map { index in
        """
            func step\(index)(input: Int) -> Int {
                let doubled = input * 2
                let shifted = doubled + \(index)
                return shifted - input
            }
        """
    }.joined(separator: "\n\n")

    private static func render(_ target: String, sources: [String]) throws -> String {
        let store = try TestSources.makeStore()
        let root = try TestSources.makeTempDirectory()
        var files: [ParsedFile] = []
        for (index, source) in sources.enumerated() {
            try files.append(TestSources.parsed(source, path: "Sources/Core/File\(index).swift", in: root))
        }
        try store.replaceFiles(files) { _ in ("Core", false) }
        let renderer = try DigestRenderer(store: store, moduleNames: store.moduleNames(), repoRoot: root)
        return try renderer.render(target: target, options: DigestOptions())
    }

    private static func noteLine(_ output: String) -> String? {
        output.split(separator: "\n").map(String.init).last { $0.hasPrefix("synthesized members") }
    }

    private static func note(_ declaration: String, target: String = "Gizmo", extra: [String] = []) throws -> String? {
        let output = try render(target, sources: ["\(declaration)\n" + padding + "\n}\n"] + extra)
        return noteLine(output)
    }

    @Test
    func plainStructNamesTheMemberwiseInit() throws {
        let line = try Self.note("struct Gizmo {\n    let id: Int\n")

        #expect(line == "synthesized members (memberwise init) not listed")
    }

    @Test
    func codableHashableStructNamesEveryItemInOrder() throws {
        let line = try Self.note("struct Gizmo: Codable, Hashable {\n    let id: Int\n")

        #expect(line == "synthesized members (memberwise init, Codable, ==, hash(into:)) not listed")
    }

    @Test
    func rawTypeCaseIterableEnumNamesRawValueInitAndAllCases() throws {
        let line = try Self.note("enum Gizmo: String, CaseIterable {\n    case small, large\n")

        #expect(line == "synthesized members (rawValue init, allCases) not listed")
    }

    @Test
    func moduleQualifiedRawTypeStillEarnsTheRawValueInit() throws {
        let line = try Self.note("enum Gizmo: Swift.Int {\n    case small = 1, large\n")

        #expect(line == "synthesized members (rawValue init) not listed")
    }

    @Test
    func payloadEnumWithoutRawTypeNamesOnlyEquality() throws {
        let line = try Self.note("public enum Gizmo: Sendable, Equatable {\n    case slim(Int)\n    case stock(String)\n")

        #expect(line == "synthesized members (==) not listed")
    }

    @Test
    func structWithAnInitAndNoConformanceGetsNoLine() throws {
        let line = try Self.note("public struct Gizmo: Sendable {\n    public init() {}\n")

        #expect(line == nil)
    }

    @Test
    func classWithoutCodableGetsNoLineAndWithCodableOnlyThat() throws {
        #expect(try Self.note("final class Gizmo {\n    init() {}\n") == nil)
        #expect(try Self.note("final class Gizmo: Codable {\n    init() {}\n") == "synthesized members (Codable) not listed")
    }

    @Test
    func protocolAndActorGetNoLine() throws {
        let requirements = (1 ... 24).map { "    /// Step \($0) of the gizmo.\n    func step\($0)(input: Int) -> Int" }.joined(separator: "\n")
        let output = try Self.render("Gizmo", sources: ["public protocol Gizmo: Sendable {\n\(requirements)\n}\n"])

        #expect(output.contains("step24"))
        #expect(Self.noteLine(output) == nil)
        #expect(try Self.note("actor Gizmo {\n    init() {}\n") == nil)
    }

    @Test
    func conformanceAddedInAnExtensionIsRead() throws {
        let line = try Self.note("struct Gizmo {\n    let id: Int\n", extra: ["extension Gizmo: Codable {}"])

        #expect(line == "synthesized members (memberwise init, Codable) not listed")
    }

    @Test
    func explicitDecodingInitLeavesOnlyEncode() throws {
        let line = try Self.note("""
        struct Gizmo: Codable {
            let id: Int
            init(from decoder: Decoder) throws {
                id = try decoder.singleValueContainer().decode(Int.self)
            }

        """)

        #expect(line == "synthesized members (encode(to:)) not listed")
    }

    @Test
    func equalityDeclaredInAnExtensionIsNotSynthesized() throws {
        let line = try Self.note("struct Gizmo: Equatable {\n    let id: Int\n", extra: ["extension Gizmo {\n    static func == (lhs: Gizmo, rhs: Gizmo) -> Bool { lhs.id == rhs.id }\n}"])

        #expect(line == "synthesized members (memberwise init) not listed")
    }
}
