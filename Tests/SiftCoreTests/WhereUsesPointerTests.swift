//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A `where` that finds no declaration of a name the tree uses says it is used and which `search` lists the uses.
@Suite(.serialized, .temporaryDirectories)
struct WhereUsesPointerTests {
    private static let usedInTwoFiles: [String: String] = [
        "Sources/App/Widget.swift": "struct Widget {\n    func load() -> Int { Gizmo.shared.placeholderCount }\n}\n",
        "Sources/App/Depot.swift": "struct Depot {\n    func load() -> Int { Gizmo.shared.placeholderCount + 1 }\n}\n",
    ]

    @Test
    func aNameUsedInTwoFilesAndDeclaredNowhereSaysSo() async throws {
        let answer = try await WhereBasenamePointerTests.answer(files: Self.usedInTwoFiles, query: "placeholderCount")

        #expect(answer.contains("no declarations found\nnot declared in this tree (an SDK or dependency symbol?); used in 2 files: search uses:placeholderCount"), "\(answer)")
    }

    @Test
    func aNameNeitherDeclaredNorUsedAddsNothing() async throws {
        let answer = try await WhereBasenamePointerTests.answer(files: Self.usedInTwoFiles, query: "executionCount")

        #expect(answer.contains("no declarations found"), "\(answer)")
        #expect(!answer.contains("not declared in this tree"), "\(answer)")
    }

    @Test
    func theNearestSymbolsAnswerCarriesTheLineToo() async throws {
        var files = Self.usedInTwoFiles
        files["Sources/App/Label.swift"] = "struct Label {\n    var placeholderCountLabel: String { \"\" }\n}\n"
        let answer = try await WhereBasenamePointerTests.answer(files: files, query: "placeholderCount")

        #expect(answer.contains("no exact match; nearest symbols:"), "\(answer)")
        #expect(answer.contains("used in 2 files: search uses:placeholderCount"), "\(answer)")
    }

    @Test
    func aDeclaredNameCarriesNoLine() async throws {
        var files = Self.usedInTwoFiles
        files["Sources/App/Label.swift"] = "struct Label {\n    var placeholderCount: Int { 1 }\n}\n"
        let answer = try await WhereBasenamePointerTests.answer(files: files, query: "placeholderCount")

        #expect(!answer.contains("not declared in this tree"), "\(answer)")
    }

    @Test
    func theBasenamePointerComesFirstWhereBothApply() async throws {
        var files = Self.usedInTwoFiles
        files["Sources/App/placeholderCount.swift"] = "extension Int {}\n"
        let answer = try await WhereBasenamePointerTests.answer(files: files, query: "placeholderCount")

        #expect(answer.contains("a file has that name: digest Sources/App/placeholderCount.swift\nnot declared in this tree"), "\(answer)")
    }

    @Test
    func atARevisionTheLineKeepsTheCountAndNamesNoCall() async throws {
        let root = try RevisionBasenamePointerTests.makeRepo(files: Self.usedInTwoFiles)
        let answer = try await SiftEngine(directory: root).lookup(symbol: "placeholderCount", at: "HEAD")

        #expect(answer.contains("not declared at HEAD (an SDK or dependency symbol?); used in 2 files there"), "\(answer)")
        #expect(!answer.contains("search uses:"), "\(answer)")
    }

    @Test
    func theToolCallFaceSpellsTheSearchAsATool() {
        let lines = WhereUsesPointer.lines(for: "placeholderCount", fileCount: 2, at: nil, spelling: .toolCall)

        #expect(lines == ["not declared in this tree (an SDK or dependency symbol?); used in 2 files: search query:\"uses:placeholderCount\""])
    }

    @Test
    func theCommandLineFaceSpellsTheSearchAsArguments() {
        let lines = WhereUsesPointer.lines(for: "placeholderCount", fileCount: 1, at: nil, spelling: .commandLine)

        #expect(lines == ["not declared in this tree (an SDK or dependency symbol?); used in 1 file: search uses:placeholderCount"])
    }

    @Test
    func aFileWithoutTheNameIsNeverParsed() async throws {
        let root = try TestSources.makeTempRepo()
        var files = Self.usedInTwoFiles
        files["Sources/App/Other.swift"] = "struct Other {\n    func load() -> Int { 1 }\n}\n"
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        let enumerator = FileEnumerator(repoRoot: root, config: SiftConfig())
        let query = try StructuralQuery("uses:placeholderCount")

        let filtered = await StructuralSearch(repoRoot: root, enumerator: enumerator, requiredText: "placeholderCount").run(query)
        let unfiltered = await StructuralSearch(repoRoot: root, enumerator: enumerator).run(query)

        #expect(filtered.filesParsed == 2)
        #expect(unfiltered.filesParsed == 3)
        #expect(filtered.matches.count == unfiltered.matches.count)
        #expect(await WhereUsesPointer.fileCount(of: "placeholderCount", repoRoot: root, enumerator: enumerator) == 2)
    }

    @Test
    func theScanPassesThePreFilterToTheSearch() async throws {
        var files = Self.usedInTwoFiles
        files["Sources/App/Other.swift"] = "struct Other {}\n"
        let (root, enumerator) = try Self.fixture(files)

        let scan = await WhereUsesPointer.scan(of: "placeholderCount", repoRoot: root, enumerator: enumerator)

        #expect(scan == WhereUsesPointer.Scan(files: 2, filesParsed: 2))
    }

    @Test
    func thePreFilterAppliesOnlyToAnAsciiNameTheQueryReadsAsWritten() throws {
        func required(_ name: String) throws -> String? {
            try WhereUsesPointer.requiredText(for: name, query: StructuralQuery("uses:\(name)"))
        }

        #expect(try required("placeholderCount") == "placeholderCount")
        #expect(try required("caf\u{E9}") == nil)
        #expect(try required("alpha|beta") == nil)
        #expect(try required("alpha beta") == nil)
    }

    @Test
    func aDecomposedNameInAFileIsCountedForAComposedName() async throws {
        let (root, enumerator) = try Self.fixture(["Sources/App/Cafe.swift": "struct Cafe {\n    func load() { cafe\u{301}() }\n}\n"])

        let scan = await WhereUsesPointer.scan(of: "caf\u{E9}", repoRoot: root, enumerator: enumerator)

        #expect(scan.files == 1)
    }

    @Test
    func aKelvinSignInAFileIsCountedForAnAsciiK() async throws {
        let (root, enumerator) = try Self.fixture([
            "Sources/App/A.swift": "struct A {\n    func load() { Kettle() }\n}\n",
            "Sources/App/B.swift": "struct B {\n    func load() { \u{212A}ettle() }\n}\n",
        ])

        let scan = await WhereUsesPointer.scan(of: "Kettle", repoRoot: root, enumerator: enumerator)

        #expect(scan.files == 2)
    }

    @Test
    func anAlternationNameCountsTheFilesUsingEitherSide() async throws {
        let (root, enumerator) = try Self.fixture([
            "Sources/App/A.swift": "struct A {\n    func load() { alpha() }\n}\n",
            "Sources/App/B.swift": "struct B {\n    func load() { beta() }\n}\n",
        ])

        let scan = await WhereUsesPointer.scan(of: "alpha|beta", repoRoot: root, enumerator: enumerator)

        #expect(scan.files == 2)
    }

    private static func fixture(_ files: [String: String]) throws -> (URL, FileEnumerator) {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        return (root, FileEnumerator(repoRoot: root, config: SiftConfig()))
    }
}
