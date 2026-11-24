//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the closing hints of `where --files` and of a long name-only `search`, and the `semantic:` word of a `where` that opened the store and found no such name.
@Suite(.temporaryDirectories, .serialized)
struct AnswerHintTests {
    private static var dropLine: String {
        "drop --files for each reference's line"
    }

    private static var narrowLine: String {
        "narrow with kind:, modifier: or owner:"
    }

    /// A committed repository of `files`, indexed.
    private static func engine(_ files: [String: String]) async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        return try SiftEngine(directory: root)
    }

    /// One file declaring `count` functions named `fetch1`, `fetch2`, and so on.
    private static func fetchers(_ count: Int) -> [String: String] {
        ["Sources/App/Fetchers.swift": (1 ... count).map { "func fetch\($0)() {}" }.joined(separator: "\n")]
    }

    private static func search(_ query: String, count: Int) async throws -> String {
        let engine = try await engine(fetchers(count))
        _ = try await engine.ensureFresh()
        return try await engine.search(query: query)
    }

    /// A listing naming a file ends with the line saying how to get each reference's line back.
    @Test
    func aFilesListingEndsWithTheDropLine() async throws {
        let engine = try await Self.engine(["Sources/App/Widget.swift": "struct Widget {}\nlet w = Widget()\n"])
        let answer = try await engine.lookup(symbol: "Widget", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true, filesOnly: true))

        #expect(answer.contains("files naming "), "\(answer)")
        #expect(answer.hasSuffix("\n" + Self.dropLine), "\(answer)")
    }

    /// A name no file writes lists no file, so no line is said.
    @Test
    func anEmptyFilesListingHasNoDropLine() async throws {
        let engine = try await Self.engine(["Sources/App/Widget.swift": "struct Widget {}\n"])
        let answer = try await engine.lookup(symbol: "Nonesuch", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true, filesOnly: true))

        #expect(!answer.contains(Self.dropLine), "\(answer)")
    }

    /// The same query without `--files` carries no such line.
    @Test
    func theRefsAnswerHasNoDropLine() async throws {
        let engine = try await Self.engine(["Sources/App/Widget.swift": "struct Widget {}\nlet w = Widget()\n"])
        let answer = try await engine.lookup(symbol: "Widget", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))

        #expect(!answer.contains(Self.dropLine), "\(answer)")
    }

    /// More than 20 declarations from a name-only query end with the narrowing line, whatever the name value's form, and `path:` beside it keeps it.
    @Test
    func aLongNameOnlyAnswerEndsWithTheNarrowingLine() async throws {
        let alternation = (1 ... 21).map { "fetch\($0)" }.joined(separator: "|")
        for query in ["name:fetch", "name:\(alternation)", "name:/^fetch/", "name:fetch path:Sources"] {
            let answer = try await Self.search(query, count: 21)

            #expect(answer.hasSuffix("\n" + Self.narrowLine), "\(query): \(answer)")
        }
    }

    /// Twenty declarations are not past the line, and a second selecting field means the query is narrowed already.
    @Test
    func otherAnswersHaveNoNarrowingLine() async throws {
        let short = try await Self.search("name:fetch", count: 20)
        let narrowed = try await Self.search("name:fetch kind:func", count: 21)
        let modified = try await Self.search("name:fetch modifier:public", count: 21)

        #expect(!short.contains(Self.narrowLine), "\(short)")
        #expect(!narrowed.contains(Self.narrowLine), "\(narrowed)")
        #expect(!modified.contains(Self.narrowLine), "\(modified)")
    }

    /// A page that lists twenty rows or fewer, a page past the end included, carries no narrowing line, however many declarations matched.
    @Test
    func aShortOrPastEndPageHasNoNarrowingLine() async throws {
        let engine = try await Self.engine(Self.fetchers(25))
        _ = try await engine.ensureFresh()
        let pastEnd = try await engine.search(query: "name:fetch", offset: 30)
        let shortPage = try await engine.search(query: "name:fetch", offset: 10)

        #expect(!pastEnd.contains(Self.narrowLine), "\(pastEnd)")
        #expect(!shortPage.contains(Self.narrowLine), "\(shortPage)")
    }

    /// With no store read, a name the index lacks keeps the word for an answer from syntax alone.
    @Test
    func aMissWithNoStoreIsNotSaidToBeInAStore() async throws {
        let engine = try await Self.engine(["Sources/App/Widget.swift": "struct Widget {}\n"])
        let answer = try await engine.lookup(symbol: "Nonesuch", freshness: engine.ensureFresh())

        #expect(answer.contains("no declarations found"), "\(answer)")
        #expect(!answer.contains("name not in the store"), "\(answer)")
    }

    /// A built package whose store is read: one declaration, `Widget`.
    private static func builtFixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "answer-hint") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(name: "Gizmo", targets: [.target(name: "GizmoCore")])
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("public struct Widget {}\n", to: "Sources/GizmoCore/Widget.swift", in: root)
            try TestSources.commitAll(in: root, message: "answer hint fixture")
            try await TestSources.swiftBuildSuspending(packageAt: root)
        }
    }

    /// A name the opened store lacks says the store's state and that the name is not in it, for the bare miss and the nearest-symbols miss alike, and an answer that found the name still says `fresh`.
    @Test
    func aMissUnderAnOpenStoreSaysTheStoresState() async throws {
        try await Self.builtFixture().withEngine { engine in
            let bare = try await engine.lookup(symbol: "Zzyzx", freshness: engine.ensureFresh())
            let near = try await engine.lookup(symbol: "Widge", freshness: engine.ensureFresh())
            let found = try await engine.lookup(symbol: "Widget", freshness: engine.ensureFresh())

            #expect(bare.contains("no declarations found"), "\(bare)")
            #expect(bare.contains("semantic: fresh, name not in the store"), "\(bare)")
            #expect(!bare.contains("syntactic-only"), "\(bare)")
            #expect(near.contains("nearest symbols:"), "\(near)")
            #expect(near.contains("semantic: fresh, name not in the store"), "\(near)")
            #expect(found.contains("semantic: fresh"), "\(found)")
            #expect(!found.contains("name not in the store"), "\(found)")
        }
    }
}
