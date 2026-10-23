//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `search` past `SearchRenderer.groupThreshold` matches at offset 0: the answer groups by file, lists whole-name matches as rows, and says how to narrow.
@Suite(.temporaryDirectories)
struct SearchGroupedPastThresholdTests {
    /// `count` matches over 15 files, the first 11 files holding three each and the rest two, named `Gizmo<n>`; the first `whole` of them whole-name matches.
    private static func result(count: Int, whole: Int) -> StructuralSearch.Result {
        let matches = (0 ..< count).map { index -> StructuralMatch in
            let file = index < 33 ? index / 3 : 11 + (index - 33) / 2
            return StructuralMatch(path: String(format: "Sources/App/Depot%02d.swift", file), line: index + 1, endLine: index + 2, kind: "func", qualifiedName: "Gizmo\(index)", signature: "func gizmo\(index)()")
        }
        return StructuralSearch.Result(matches: matches, filesScanned: 90, wholeNameMatches: whole)
    }

    private static func rendered(_ result: StructuralSearch.Result, offset: Int = 0) throws -> String {
        try SearchRenderer.render(result: result, query: StructuralQuery("kind:func"), offset: offset)
    }

    @Test
    func pastTheThresholdTheAnswerIsTheFileListWithWholeNameRowsOnly() throws {
        let answer = try Self.rendered(Self.result(count: 41, whole: 7))
        let lines = answer.split(separator: "\n").map(String.init)

        #expect(lines.contains("41 declaration(s) in 15 file(s) — scanned 90 file(s); grouped by file past 40"), "\(answer)")
        #expect(lines.filter { $0.hasPrefix("  3  Sources/") || $0.hasPrefix("  2  Sources/") }.count == 12, "\(answer)")
        #expect(lines.contains("  3  Sources/App/Depot00.swift"), "\(answer)")
        #expect(lines.contains("  + 3 more files (6 matches)"), "\(answer)")
        #expect(lines.contains("whole-name matches (7):"), "\(answer)")
        #expect(lines.filter { $0.hasPrefix("  :") }.count == 5, "\(answer)")
        #expect(lines.contains("  :5-6  Gizmo4 — func gizmo4()"), "\(answer)")
        #expect(!answer.contains("Gizmo20"), "\(answer)")
        #expect(!answer.contains("whose whole name matches come first"), "\(answer)")
        #expect(lines.last == "narrow with path:Depot00.swift, owner:<Type>, kind:, or a tighter name:; offset 5 continues the listing", "\(answer)")
    }

    @Test
    func withNoWholeNameMatchTheRowsAreTheFirstFiveMatchesAndTheClauseIsOffsetFive() throws {
        let answer = try Self.rendered(Self.result(count: 41, whole: 0))
        let lines = answer.split(separator: "\n").map(String.init)

        #expect(!answer.contains("whole-name matches"), "\(answer)")
        #expect(lines.contains("first 5:"), "\(answer)")
        #expect(lines.filter { $0.hasPrefix("  :") }.count == 5, "\(answer)")
        #expect(lines.contains("  :1-2  Gizmo0 — func gizmo0()"), "\(answer)")
        #expect(answer.hasSuffix("; offset 5 continues the listing"), "\(answer)")
    }

    @Test
    func aResultInOneFileIsNotGrouped() throws {
        let matches = (0 ..< 42).map { StructuralMatch(path: "Sources/App/Only.swift", line: $0 + 1, endLine: $0 + 2, kind: "func", qualifiedName: "Gizmo\($0)", signature: "func gizmo\($0)()") }
        let answer = try Self.rendered(StructuralSearch.Result(matches: matches, filesScanned: 3, wholeNameMatches: 0))

        #expect(!answer.contains("grouped by file"), "\(answer)")
        #expect(!answer.contains("narrow with"), "\(answer)")
        #expect(answer.contains("Gizmo41"), "\(answer)")
    }

    @Test
    func countsAreRightAlignedAndABasenameWithWhitespaceIsQuoted() throws {
        var matches = (0 ..< 30).map { StructuralMatch(path: "Sources/App/Big Gizmo.swift", line: $0 + 1, endLine: $0 + 2, kind: "func", qualifiedName: "Gizmo\($0)", signature: "func gizmo\($0)()") }
        matches += (0 ..< 12).map { StructuralMatch(path: "Sources/App/Small\($0 < 8 ? 0 : 1).swift", line: $0 + 1, endLine: $0 + 2, kind: "func", qualifiedName: "Widget\($0)", signature: "func widget\($0)()") }
        let answer = try Self.rendered(StructuralSearch.Result(matches: matches, filesScanned: 3, wholeNameMatches: 0))
        let lines = answer.split(separator: "\n").map(String.init)

        #expect(lines.contains("   8  Sources/App/Small0.swift"), "\(answer)")
        #expect(lines.contains("   4  Sources/App/Small1.swift"), "\(answer)")
        #expect(lines.contains("  30  Sources/App/Big Gizmo.swift"), "\(answer)")
        #expect(lines.contains { $0.hasPrefix("narrow with path:\"Big Gizmo.swift\",") }, "\(answer)")
    }

    @Test
    func exactlyTheThresholdKeepsTheRowListing() throws {
        let answer = try Self.rendered(Self.result(count: 40, whole: 7))

        #expect(!answer.contains("grouped by file"), "\(answer)")
        #expect(!answer.contains("narrow with"), "\(answer)")
        #expect(answer.contains("  :40-41  Gizmo39 — func gizmo39()"), "\(answer)")
    }

    @Test
    func aLaterOffsetKeepsThePagedRowListing() throws {
        let answer = try Self.rendered(Self.result(count: 41, whole: 7), offset: 2)

        #expect(!answer.contains("grouped by file"), "\(answer)")
        #expect(answer.contains("(…2 matches skipped)"), "\(answer)")
    }

    @Test
    func aDoubleQuotedPathValueHoldingSpacesMatchesFilesUnderThatDirectory() async throws {
        let root = try TemporaryDirectory.make("search-quoted-path")
        let files = ["Dir With Space/Inside.swift": "struct Inside {}", "Other/Outside.swift": "struct Outside {}"]
        for (path, source) in files {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: file, atomically: true, encoding: .utf8)
        }
        let enumerator = FileEnumerator(repoRoot: root, config: SiftConfig(), gitListing: { files.keys.sorted() })
        let parsed = try StructuralQuery("kind:struct path:\"Dir With Space/\"")
        let result = await StructuralSearch(repoRoot: root, enumerator: enumerator).run(parsed)

        #expect(result.matches.map(\.qualifiedName) == ["Inside"], "\(result.matches)")
    }
}
