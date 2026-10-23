//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Which properties count as holding a literal, and which of their uses a row lists.
@Suite(.temporaryDirectories)
struct StringsPropertyHolderShapeTests {
    private static func makeRepo(files: [String: String]) throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        for (path, contents) in files {
            try TestSources.write(contents, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "holder shape fixture")
        return try SiftEngine(directory: root)
    }

    @Test
    func aViewBodyShowingTheTextIsNotItsHolder() throws {
        let source = """
        struct Gizmo {
            var body: some View {
                Text("Gizmo label")
            }
        }
        struct Depot {
            var body: some View { Text("other") }
        }
        """
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/View.swift": source])

        let output = try engine.strings(query: "Gizmo label")

        #expect(output.contains("Gizmo.body — Sources/Gizmo/View.swift:3"))
        #expect(!output.contains("      "))
    }

    @Test
    func aLocalisationCallInitialiserHoldsTheLiteral() throws {
        let source = """
        struct Gizmo {
            private static let gone = NSLocalizedString("gizmo-gone", value: "Gizmo is gone", comment: "shown when gone")
            func show() { present(Self.gone) }
        }
        """
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": source])

        let output = try engine.strings(query: "Gizmo is gone")

        #expect(output.contains("      Sources/Gizmo/Gizmo.swift:3 in Gizmo.show(): func show() { present(Self.gone) }"))
    }

    @Test
    func aHolderSharedByTwoRowsPrintsItsTrailOnce() throws {
        let source = """
        struct Gizmo {
            static let both = NSLocalizedString(
                "Gizmo twin",
                value: "Gizmo twin",
                comment: ""
            )
            func show() { present(Self.both) }
        }
        """
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": source])

        let output = try engine.strings(query: "Gizmo twin")

        #expect(output.components(separatedBy: "Gizmo.swift:").count - 1 >= 3)
        #expect(output.components(separatedBy: "present(Self.both)").count - 1 == 1)
    }

    @Test
    func aHolderWithFiveUsesListsThreeDeclaringFileFirst() throws {
        let holder = """
        struct Gizmo {
            static let missing = "Gizmo went missing"
            func one() { present(Self.missing) }
        }
        """
        var files = ["Sources/Gizmo/A.swift": "func a1() { _ = Gizmo.missing }\nfunc a2() { _ = Gizmo.missing }", "Sources/Gizmo/B.swift": "func b1() { _ = Gizmo.missing }\nfunc b2() { _ = Gizmo.missing }"]
        files["Sources/Gizmo/Z.swift"] = holder
        let engine = try Self.makeRepo(files: files)

        let output = try engine.strings(query: "Gizmo went missing")

        let uses = output.split(separator: "\n").filter { $0.hasPrefix("      Sources/") }

        #expect(uses.count == 3)
        #expect(uses.first?.hasPrefix("      Sources/Gizmo/Z.swift:3 in Gizmo.one()") == true)
        #expect(output.contains("      +2 more sites — where missing lists them all"))
    }

    @Test
    func aStaticHolderIgnoresASameNamedInstanceMemberElsewhere() throws {
        let holder = """
        struct Gizmo {
            static let missing = "Gizmo went missing"
            func show() { present(Self.missing) }
        }
        """
        let other = """
        struct Widget {
            let missing = 1
            func go() { _ = missing + self.missing; _ = Widget().missing }
        }
        """
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": holder, "Sources/Gizmo/Widget.swift": other])

        let output = try engine.strings(query: "Gizmo went missing")

        #expect(output.contains("Gizmo.swift:3 in Gizmo.show()"))
        #expect(!output.contains("Widget.swift"))
    }

    @Test
    func aStaticHolderKeepsTheBareNameInsideItsTypeAndAnExtension() throws {
        let holder = """
        struct Gizmo {
            static let missing = "Gizmo went missing"
            func show() { present(missing) }
        }
        """
        let extended = "extension Gizmo {\n    func again() { present(missing) }\n}"
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": holder, "Sources/Gizmo/More.swift": extended])

        let output = try engine.strings(query: "Gizmo went missing")

        #expect(output.contains("Gizmo.swift:3 in Gizmo.show()"))
        #expect(output.contains("More.swift:2 in Gizmo.again()"))
    }
}

extension StringsPropertyHolderShapeTests {
    @Test
    func sevenHoldersFollowTrailsForOnlyTheFiveThePrintedAnswerLists() throws {
        let holders = (1 ... 7).map { "    static let gizmo\($0) = \"Gizmo shared text \($0)\"" }.joined(separator: "\n")
        let root = try TestSources.makeTempRepo()
        try TestSources.write("struct Gizmo {\n\(holders)\n}\n", to: "Sources/Gizmo/Gizmo.swift", in: root)
        try TestSources.commitAll(in: root, message: "seven holders")
        let paths = { ["Sources/Gizmo/Gizmo.swift"] }
        let search = StringCatalogSearch(repoRoot: root, catalogPaths: { [] }, swiftPaths: paths, cache: StringCatalogCache())
        let sites = SourceLiteralSearch(repoRoot: root, swiftPaths: paths).run(query: "Gizmo shared text", catalogAnswered: false)
        #expect(sites.count(where: { $0.holder != nil }) == 7)

        var asked: [[String]] = []
        let followed = search.followingProperties(in: sites, query: "Gizmo shared text") { names in
            asked.append(names)
            return [:]
        }

        #expect(asked.count == 1)
        #expect(asked.first?.count == SourceLiteralSearch.propertyUseCap)
        #expect(followed.count(where: { $0.uses != nil }) == SourceLiteralSearch.propertyUseCap)
    }
}
