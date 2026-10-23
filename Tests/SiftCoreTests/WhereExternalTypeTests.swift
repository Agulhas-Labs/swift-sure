//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `where Dep.member` with no index store, for a `Dep` the repository writes and declares nowhere: the answer says the type is declared outside the repository and lists the member's uses by written name, never that the member is declared but not under the type.
@Suite(.temporaryDirectories)
struct WhereExternalTypeTests {
    /// A dependency's `Tally` written only as a parameter's type, its `Meter` only extended, a generic parameter `T` written in an extension of the type declaring it, and a repository type declaring a `count` of its own.
    private static let files = [
        "Sources/App/Widget.swift": "struct Widget {\n    var count: Int { 1 }\n}\n",
        "Sources/App/Total.swift": "import Dep\n\nfunc total(_ tally: Tally, _ widget: Widget) -> Int {\n    let first = tally.count\n    return first + widget.count\n}\n",
        "Sources/App/Meter.swift": "import Dep\n\nextension Meter {\n    var doubled: Int { 2 }\n}\n",
        "Sources/App/Box.swift": "struct Box<T> {}\n\nextension Box {\n    func read(_ value: T) -> T {\n        value\n    }\n}\n",
    ]

    /// The answer `where` gives for `symbol` over the fixture and `extraFiles`, with no index store.
    private static func answer(_ symbol: String, options: WhereOptions = WhereOptions(), extraFiles: [String: String] = [:]) async throws -> String {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files.merging(extraFiles, uniquingKeysWith: { $1 }) {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "a dependency's types, unbuilt")
        let engine = try SiftEngine(directory: root)
        return try await engine.lookup(symbol: symbol, freshness: engine.ensureFresh(), options: options)
    }

    /// A type written as a parameter's type and declared nowhere is said to be declared outside the repository, and the member's uses are listed by written name, a same-named member of another type among them.
    @Test
    func aWrittenUndeclaredTypeIsDeclaredOutsideAndItsMemberListedByWrittenName() async throws {
        let output = try await Self.answer("Tally.count", options: WhereOptions(includeReferences: true))

        #expect(output.contains("Tally is declared outside this repository"), "\(output)")
        #expect(!output.contains("declared, but not under"), "\(output)")
        #expect(output.contains("\"count\" (2 uses by written name in 1 file; a same-named member of another type may be among them):"), "\(output)")
        #expect(output.contains("Sources/App/Total.swift:\n    :4  in total(_:_:).first  | let first = tally.count\n    :5  in total(_:_:)  | return first + widget.count"), "\(output)")
    }

    /// A type the repository only extends is declared outside it too, and its extension is listed as `digest` lists it.
    @Test
    func anExtendedUndeclaredTypeListsItsExtension() async throws {
        let output = try await Self.answer("Meter.count")

        #expect(output.contains("Meter is declared outside this repository"), "\(output)")
        #expect(output.contains("extensions of Meter (1):\n  extension Meter — Sources — Sources/App/Meter.swift:3-5"), "\(output)")
        #expect(!output.contains("declared, but not under"), "\(output)")
    }

    /// A generic parameter written in an extension of the type whose generic clause declares it is declared there, so a member asked of it keeps the wrong-path answer.
    @Test
    func aGenericParameterIsNotDeclaredOutside() async throws {
        let output = try await Self.answer("T.count")

        #expect(!output.contains("declared outside this repository"), "\(output)")
        #expect(output.contains("could not resolve the path T.count — count is declared, but not under T:"), "\(output)")
    }

    /// A type the repository neither declares nor writes keeps the wrong-path answer.
    @Test
    func anUnwrittenUndeclaredTypeKeepsTheWrongPathAnswer() async throws {
        let output = try await Self.answer("Missing.count")

        #expect(!output.contains("declared outside this repository"), "\(output)")
        #expect(output.contains("could not resolve the path Missing.count — count is declared, but not under Missing:"), "\(output)")
    }

    /// The repository's own declarations of the member's name, on other types, are listed under a heading that never says the member is not under the type.
    @Test
    func theRepositorysSameNamedMembersAreListed() async throws {
        let output = try await Self.answer("Tally.count")

        #expect(output.contains("other declarations of count in this repository (1):\n  Sources.Widget.count — var — Sources/App/Widget.swift:2"), "\(output)")
        #expect(!output.contains("not under Tally"), "\(output)")
    }

    /// A file the parser could not finish may hold the type's declaration, so the answer carries the absence banner above its headline and does not say the type is declared outside the repository.
    @Test
    func aParseErrorElsewhereCarriesTheBannerAndSoftensTheClaim() async throws {
        let output = try await Self.answer("Tally.count", extraFiles: ["Sources/App/Broken.swift": "struct Truncated {\n    func swallowedFromHereOn(\n}\n"])
        let lines = output.split(separator: "\n").map(String.init)

        let banner = try #require(lines.firstIndex { $0.hasPrefix("⚠ parse errors elsewhere in this repo") }, "\(output)")
        let claim = try #require(lines.firstIndex { $0.hasPrefix("Tally is declared in no file the index read in full") }, "\(output)")

        #expect(banner < claim, "\(output)")
        #expect(output.contains("Sources/App/Broken.swift"), "\(output)")
        #expect(!output.contains("Tally is declared outside this repository"), "\(output)")
    }

    /// The files view names the file holding the repository's extension of the type.
    @Test
    func theFilesViewListsTheExtensionsFile() async throws {
        let output = try await Self.answer("Meter.count", options: WhereOptions(filesOnly: true))

        #expect(output.split(separator: "\n").contains("  Sources/App/Meter.swift (declares)"), "\(output)")
    }
}
