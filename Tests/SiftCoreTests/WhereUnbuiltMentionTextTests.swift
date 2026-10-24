//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The lines a `where` lists as written outside the build close on the line's text where there are few of them, so a caller does not open the files to read them.
@Suite(.serialized, .temporaryDirectories)
struct WhereUnbuiltMentionTextTests {
    private static var heading: String {
        "not in the build, mention the name:"
    }

    /// A few mentions list one row per line under each file, files in path order and lines ascending, each closing on the line's text, a string mention included, and a line that cannot be read printing without it.
    @Test
    func fewMentionsListOneRowPerLineWithTheText() throws {
        let root = try TestSources.makeTempDirectory()
        try TestSources.write("let a = 1\n    gizmo.record(\n\n\"gizmo\"\n", to: "Fixtures/BetaTests.swift", in: root)
        try TestSources.write("widget.spin()\n", to: "Fixtures/AlphaTests.swift", in: root)
        let mentions = [
            NameMention(path: "Fixtures/AlphaTests.swift", line: 1),
            NameMention(path: "Fixtures/BetaTests.swift", line: 2),
            NameMention(path: "Fixtures/BetaTests.swift", line: 3),
            NameMention(path: "Fixtures/BetaTests.swift", line: 4),
            NameMention(path: "Fixtures/BetaTests.swift", line: 9),
        ]

        let rows = WhereUnbuiltMentions.rows(listing: mentions, under: root.path)

        #expect(rows == [
            Self.heading,
            "  Fixtures/AlphaTests.swift (1):",
            "    :1  | widget.spin()",
            "  Fixtures/BetaTests.swift (4):",
            "    :2  | gizmo.record(",
            "    :3",
            "    :4  | \"gizmo\"",
            "    :9",
        ], "\(rows)")
    }

    /// Past the line cap the one compact line stands, exactly as it is without the text.
    @Test
    func moreThanTheCapStaysCompact() throws {
        let root = try TestSources.makeTempDirectory()
        let lines = Array(1 ... WhereRenderer.siteTextLineCap + 1)
        try TestSources.write(lines.map { _ in "gizmo.record()" }.joined(separator: "\n") + "\n", to: "Fixtures/GizmoTests.swift", in: root)
        let mentions = lines.map { NameMention(path: "Fixtures/GizmoTests.swift", line: $0) }

        let rows = WhereUnbuiltMentions.rows(listing: mentions, under: root.path)
        let capped = WhereUnbuiltMentions.rows(listing: Array(mentions.dropLast()), under: root.path)

        let compact = try #require(WhereUnbuiltMentions.line(listing: mentions))

        #expect(rows == [compact], "\(rows)")
        #expect(rows.count == 1 && !rows[0].contains("|"), "\(rows)")
        #expect(capped.count == WhereRenderer.siteTextLineCap + 2, "\(capped)")
    }

    /// Files counted as not scanned close the rows as one more row, and with no mention to list the compact line, which says none was found, stands.
    @Test
    func theUnscannedFilesAreTheLastRow() throws {
        let root = try TestSources.makeTempDirectory()
        try TestSources.write("gadget.run()\n", to: "Fixtures/GadgetTests.swift", in: root)
        let mentions = [NameMention(path: "Fixtures/GadgetTests.swift", line: 1)]

        let some = WhereUnbuiltMentions.rows(listing: mentions, unscanned: 3, under: root.path)
        let one = WhereUnbuiltMentions.rows(listing: mentions, unscanned: 1, under: root.path)
        let none = WhereUnbuiltMentions.rows(listing: [], unscanned: 2, under: root.path)
        let nothing = WhereUnbuiltMentions.rows(listing: [], under: root.path)

        #expect(some.last == "  3 outside files not scanned", "\(some)")
        #expect(some.count == 4, "\(some)")
        #expect(one.last == "  1 outside file not scanned", "\(one)")
        #expect(none == ["\(Self.heading) none in the files scanned · 2 outside files not scanned"], "\(none)")
        #expect(nothing.isEmpty, "\(nothing)")
    }

    /// A built package whose `Fixtures/WidgetTests.swift`, outside every target, writes `Gizmo` on one line.
    private static func strayFileEngine() async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(
            "// swift-tools-version:5.9\nimport PackageDescription\n\nlet package = Package(\n    name: \"Lib\",\n    targets: [.target(name: \"Lib\"), .testTarget(name: \"LibTests\", dependencies: [\"Lib\"])]\n)\n",
            to: "Package.swift",
            in: root
        )
        try TestSources.write("public struct Gizmo {\n    public var walk = 1\n    public init() {}\n}\n", to: "Sources/Lib/Gizmo.swift", in: root)
        try TestSources.write("@testable import Lib\nimport Testing\n\n@Test func reads() {\n    #expect(Gizmo().walk == 1)\n}\n", to: "Tests/LibTests/GadgetTests.swift", in: root)
        try TestSources.write(
            "@testable import Lib\nimport Testing\n\n@Test func strays() {\n    #expect(   Gizmo().walk  == 1)\n}\n",
            to: "Fixtures/WidgetTests.swift",
            in: root
        )
        try TestSources.commitAll(in: root, message: "seed")
        try await TestSources.swiftBuildSuspending(packageAt: root, includingTests: true)
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()
        return engine
    }

    /// An end-to-end `where --refs` answer lists the stray test file's line with its text, under its file, after a blank line.
    @Test
    func aRefsAnswerListsTheStrayFileLineWithItsText() async throws {
        let engine = try await Self.strayFileEngine()

        let answer = try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))
        let rows = answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let start = try #require(rows.firstIndex(of: Self.heading), "\(answer)")

        #expect(Array(rows[start ... start + 2]) == [Self.heading, "  Fixtures/WidgetTests.swift (1):", "    :5  | #expect( Gizmo().walk == 1)"], "\(answer)")
        #expect(start > 0 && rows[start - 1] == "", "\(answer)")
    }

    /// A `--files` sweep keeps no indented row, so it lists the stray file's line in the compact form.
    @Test
    func aFilesAnswerKeepsTheCompactMentionLine() async throws {
        let engine = try await Self.strayFileEngine()

        let answer = try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: WhereOptions(filesOnly: true))

        #expect(answer.contains("\(Self.heading) Fixtures/WidgetTests.swift:5"), "\(answer)")
        #expect(!answer.contains("    :5"), "\(answer)")
    }

    /// Without `--refs`, files of one mention each still list as rows while the mentions number at most the cap: no file is cut for being many.
    @Test
    func manyFilesOfOneMentionEachStillListAsRows() throws {
        let root = try TestSources.makeTempDirectory()
        let mentions = try (1 ... 12).map { number -> NameMention in
            let path = "Fixtures/Widget\(number)Tests.swift"
            try TestSources.write("gizmo.record()\n", to: path, in: root)
            return NameMention(path: path, line: 1)
        }

        let rows = WhereUnbuiltMentions.rows(listing: mentions, under: root.path)

        #expect(rows.count { $0.hasSuffix("(1):") } == 12, "\(rows)")
        #expect(!rows.contains { $0.contains("more file") }, "\(rows)")
    }
}
