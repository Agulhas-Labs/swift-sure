//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `where X --decl` answers where X is declared from the syntactic index alone: digest's header, the declarations, and one line naming what it left out.
@Suite(.temporaryDirectories)
struct WhereDeclarationsOnlyTests {
    static var shapes: String {
        """
        protocol Runner {}

        struct Gizmo: Runner {
            let size: Int
            func spin() {}
        }

        struct Alpha { func run() {} }
        struct Beta { func run() {} }

        class Base {
            let size: Int
            init(size: Int) { self.size = size }
        }

        final class Sub: Base {}

        struct Point {
            let x: Int
        }

        struct Widget {
            init(count: Int) {}
        }

        final class Leaf: NSObject {}

        final class Holder {
            deinit {}
        }

        enum Outer {
            struct Widget { let x: Int }
        }

        enum Maker {
            static func make() -> Int {
                let gizmo = Gizmo(size: 1)
                let sub = Sub(size: 1)
                let point = Point(x: 1)
                Alpha().run()
                return gizmo.size + sub.size + point.x
            }
        }
        """
    }

    static var pointer: String {
        "without --decl covers its uses, extensions, conformers, callers and overrides."
    }

    static func fixture(_ source: String = shapes) async throws -> (engine: SiftEngine, freshness: Freshness) {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(source, to: "Sources/App/Shapes.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let engine = try SiftEngine(directory: root)
        return try await (engine, engine.ensureFresh())
    }

    static func decl(_ symbol: String, source: String = shapes, offset: Int = 0) async throws -> String {
        let (engine, freshness) = try await fixture(source)
        return try await engine.lookup(symbol: symbol, freshness: freshness, options: WhereOptions(offset: offset, declarationsOnly: true))
    }

    static func plain(_ symbol: String, source: String = shapes) async throws -> String {
        let (engine, freshness) = try await fixture(source)
        return try await engine.lookup(symbol: symbol, freshness: freshness)
    }

    /// The store's own lines, which a `--decl` answer never carries whatever state the store is in.
    static let storeLines = ["semantic:", "no store for", "stores:", "NOT ANSWERED", "degraded", "not asked for", "by written name"]

    @Test
    func aTypeAnswersDigestsHeaderItsDeclarationsAndThePointerLast() async throws {
        let plain = try await Self.plain("Gizmo")
        let output = try await Self.decl("Gizmo")
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(plain.contains("semantic:"), "\(plain)")
        #expect(!(lines.first ?? "").contains("semantic:"), "\(output)")
        #expect(lines.first?.hasPrefix("tree:") == true, "\(output)")
        #expect(output.contains("declarations (1):"), "\(output)")
        #expect(output.contains("Gizmo — struct"), "\(output)")
        #expect(lines.last == "`where Gizmo` \(Self.pointer)", "\(output)")
        // The pointer line names what was left out, so it is set aside before checking none of it is there.
        let body = lines.dropLast().joined(separator: "\n")
        for absent in ["used by", "extensions of", "conformers of", "NOT ANSWERED", "callers"] + Self.storeLines {
            #expect(!body.contains(absent), "\(absent): \(output)")
        }
    }

    @Test
    func severalOwnersPrintThePlainBlockNotTheOwnerForm() async throws {
        let output = try await Self.decl("run")

        #expect(output.contains("declarations (2):"), "\(output)")
        #expect(!output.contains("owners"), "\(output)")
        #expect(!output.split(separator: "\n").dropLast().joined(separator: "\n").contains("uses"), "\(output)")
        #expect(output.hasSuffix("`where run` \(Self.pointer)"), "\(output)")
    }

    @Test
    func aBlockCutByItsCapPointsOnToTheAnswerThatListsTheRest() async throws {
        let extensions = (0 ..< 45).map { "extension Gizmo { func spin\($0)() {} }" }.joined(separator: "\n")
        let source = "struct Gizmo {}\n" + extensions + "\n"
        let plain = try await Self.plain("Gizmo", source: source)
        let output = try await Self.decl("Gizmo", source: source)

        #expect(plain.contains("truncated: 6 more declarations, 6 of them under extensions of Gizmo"), "\(plain)")
        #expect(output.contains("truncated: 6 more declarations — where Gizmo lists 6 of them under extensions of Gizmo"), "\(output)")
    }

    @Test
    func aMemberwiseInitializerKeepsItsProvenanceWithoutTheCallsBelow() async throws {
        let output = try await Self.decl("Point.init")

        #expect(output.contains("Point declares no init — the compiler writes its memberwise initializer"), "\(output)")
        #expect(!output.contains("calls below"), "\(output)")
        #expect(!output.contains("call site"), "\(output)")
        #expect(output.split(separator: "\n").last == "`where Point.init` \(Self.pointer)", "\(output)")
        for absent in Self.storeLines {
            #expect(!output.contains(absent), "\(absent): \(output)")
        }
    }

    @Test
    func anInheritedInitializerKeepsItsProvenanceWithoutTheCallsBelow() async throws {
        let output = try await Self.decl("Sub.init")

        #expect(output.contains("Sub declares no init — it inherits Base's initializers; where Base.init lists them"), "\(output)")
        #expect(!output.contains("calls below"), "\(output)")
        #expect(!output.contains("call site"), "\(output)")
        #expect(output.split(separator: "\n").last == "`where Sub.init` \(Self.pointer)", "\(output)")
        for absent in Self.storeLines {
            #expect(!output.contains(absent), "\(absent): \(output)")
        }
    }

    @Test
    func aSubclassOfAnSDKTypeKeepsTheThirdProvenanceSentence() async throws {
        let output = try await Self.decl("Leaf.init")

        #expect(output.contains("Leaf declares no init — it has one it inherits from NSObject, if that is its superclass, or the default init() the compiler writes"), "\(output)")
        #expect(output.split(separator: "\n").last == "`where Leaf.init` \(Self.pointer)", "\(output)")
    }

    @Test
    func aDeinitEndsWithoutThePointerLine() async throws {
        let output = try await Self.decl("Holder.deinit")

        #expect(output.contains("deinit"), "\(output)")
        #expect(!output.contains(Self.pointer), "\(output)")
        #expect(!output.contains("without --decl"), "\(output)")
    }

    @Test
    func theStoreIsNeverProbedForADeclarationsOnlyLookup() async throws {
        let (engine, freshness) = try await Self.fixture()
        // Freshening probes the store for the deletion ledger, so the mark is cleared first: only a lookup can set it again.
        engine.probedStore = nil
        _ = try await engine.lookup(symbol: "Gizmo", freshness: freshness, options: WhereOptions(declarationsOnly: true))
        let afterDecl = engine.probedStore == nil

        _ = try await engine.lookup(symbol: "Gizmo", freshness: freshness)
        let afterPlain = engine.probedStore != nil

        #expect(afterDecl)
        #expect(afterPlain, "a plain lookup is the control: it probes the store")
    }

    @Test
    func theBlockOfTypesWithNoInitOfTheirOwnIsKeptWithoutItsSites() async throws {
        let plain = try await Self.plain("Widget.init")
        let output = try await Self.decl("Widget.init")

        #expect(plain.contains("declared with no init of their own (1):"), "\(plain)")
        #expect(output.contains("declared with no init of their own (1):"), "\(output)")
        #expect(output.contains("Outer.Widget — struct"), "\(output)")
        #expect(output.contains("Outer.Widget declares no init — the compiler writes its memberwise initializer"), "\(output)")
        #expect(!output.contains("calls below"), "\(output)")
        #expect(!output.contains("call site"), "\(output)")
        #expect(output.split(separator: "\n").last == "`where Widget.init` \(Self.pointer)", "\(output)")
        for absent in Self.storeLines {
            #expect(!output.contains(absent), "\(absent): \(output)")
        }
    }

    @Test
    func aMissKeepsItsBodyWithNoPointerLineAndNoStoreLines() async throws {
        let output = try await Self.decl("Nonexistent")

        #expect(output.contains("no declarations found"), "\(output)")
        #expect(!output.contains(Self.pointer), "\(output)")
        for absent in Self.storeLines {
            #expect(!output.contains(absent), "\(absent): \(output)")
        }
    }

    @Test
    func theNearestSymbolsKeepTheirBodyWithNoPointerLine() async throws {
        let output = try await Self.decl("Gizm")

        #expect(output.contains("no exact match; nearest symbols:"), "\(output)")
        #expect(!output.contains(Self.pointer), "\(output)")
        #expect(!output.contains("semantic:"), "\(output)")
    }

    @Test
    func anAnswerAtARevisionKeepsItsOwnHeaderAndListsNoCallers() async throws {
        let (engine, _) = try await Self.fixture()
        let output = try await engine.lookup(symbol: "Alpha.run", at: "HEAD", options: WhereOptions(declarationsOnly: true))

        #expect(output.hasPrefix("tree:"), "\(output)")
        #expect(output.contains("at: HEAD = "), "\(output)")
        #expect(!output.contains("semantic:"), "\(output)")
        #expect(output.contains("declarations (1):"), "\(output)")
        #expect(!output.contains("by written name"), "\(output)")
        #expect(output.split(separator: "\n").last == "`where Alpha.run` \(Self.pointer)", "\(output)")
    }

    @Test
    func anOffsetIsNamedUnusedAfterThePointer() async throws {
        let output = try await Self.decl("Gizmo", offset: 3)
        let lines = output.split(separator: "\n")

        #expect(lines.count >= 2)
        #expect(lines[lines.count - 2] == "`where Gizmo` \(Self.pointer)", "\(output)")
        #expect(lines.last?.hasPrefix("(offset 3 unused") == true, "\(output)")
    }

    // MARK: A small declaration's source follows its row

    /// A 5-line enum on lines 3-7, in a file of its own so its line numbers are known.
    static var orchard: String {
        """
        import Foundation

        enum Orchard: String {
            case apple
            case pear
            case plum
        }
        """
    }

    /// A struct of `count + 2` lines whose members are named `<name>1…<name>count`.
    static func widget(_ name: String, members count: Int) -> String {
        "struct \(name) {\n" + (1 ... count).map { "    let \(name.lowercased())\($0) = \($0)\n" }.joined() + "}\n"
    }

    @Test
    func aSmallDeclarationsSourceIsNumberedBetweenItsRowAndThePointer() async throws {
        let output = try await Self.decl("Orchard", source: Self.orchard)
        let lines = output.components(separatedBy: "\n")
        let row = try #require(lines.firstIndex { $0.contains("Orchard — enum") })

        let after = Array(lines.dropFirst(row + 1))

        #expect(after.first == "     3\tenum Orchard: String {", "\(output)")
        #expect(after.dropFirst().first == "     4\t    case apple", "\(output)")
        #expect(after.dropFirst(4).first == "     7\t}", "\(output)")
        #expect(after.dropFirst(5).first == "`where Orchard` \(Self.pointer)", "\(output)")
    }

    @Test
    func aDeclarationOverTheRowCapGetsNoSource() async throws {
        let output = try await Self.decl("Big", source: Self.widget("Big", members: 29))

        #expect(output.contains("Big — struct"), "\(output)")
        #expect(!output.contains("\tstruct Big {"), "\(output)")
        #expect(!output.contains("\tlet big1"), "\(output)")
    }

    @Test
    func aDeclarationAtTheRowCapGetsItsSource() async throws {
        let output = try await Self.decl("Edge", source: Self.widget("Edge", members: 28))

        #expect(output.contains("     1\tstruct Edge {"), "\(output)")
        #expect(output.contains("    30\t}"), "\(output)")
    }

    @Test
    func rowsInlineInPrintedOrderUntilOneWouldPassTheAnswerCapAndNoLaterRowDoes() async throws {
        // Three 14-line Gadgets then a 3-line one: 14 + 14 = 28 inline, the third would reach 42, and the fourth, which would fit, still gets none.
        let nested = [("a", "Depot"), ("b", "Catalogue"), ("c", "Orchard")].map { owner, holder in
            "enum \(holder) {\n    struct Gadget {\n" + (1 ... 12).map { "        let \(owner)\($0) = 0\n" }.joined() + "    }\n}\n"
        }.joined()
        let source = nested + "enum Gizmo {\n    struct Gadget { let d1 = 0 }\n}\n"
        let output = try await Self.decl("Gadget", source: source)
        let numbered = output.components(separatedBy: "\n").filter { $0.range(of: #"^ *\d+\t"#, options: .regularExpression) != nil }

        #expect(numbered.count == 28, "\(numbered.count) numbered lines\n\(output)")
        #expect(output.contains("let a1"), "\(output)")
        #expect(output.contains("let b1"), "\(output)")
        #expect(!output.contains("let c1"), "\(output)")
        #expect(!output.contains("let d1 = 0 }\n"), "\(output)")
    }

    @Test
    func anExtensionRowGetsNoSource() async throws {
        let source = "struct Gizmo {}\n\nextension Gizmo {\n    func spin() {}\n}\n"
        let output = try await Self.decl("Gizmo", source: source)

        #expect(output.contains("extension"), "\(output)")
        #expect(!output.contains("     3\textension Gizmo {"), "\(output)")
        #expect(!output.contains("     4\t    func spin() {}"), "\(output)")
    }

    @Test
    func aPlainWhereCarriesNoNumberedSource() async throws {
        let (engine, freshness) = try await Self.fixture(Self.orchard)
        let output = try await engine.lookup(symbol: "Orchard", freshness: freshness, options: WhereOptions())

        #expect(output.contains("Orchard — enum"), "\(output)")
        #expect(!output.contains("     3\tenum Orchard: String {"), "\(output)")
    }

    // MARK: What skips a row and what ends inlining

    /// Two `Gadget`s in the printed order of their files: the first of `first` members, the second of `second`.
    static func twoGadgets(_ first: Int, _ second: Int) -> String {
        func gadget(_ holder: String, _ count: Int) -> String {
            "enum \(holder) {\n    struct Gadget {\n" + (1 ... count).map { "        let \(holder.lowercased())\($0) = 0\n" }.joined() + "    }\n}\n"
        }
        return gadget("Depot", first) + gadget("Orchard", second)
    }

    @Test
    func aRowOverTheRowCapIsSkippedAndTheSmallRowAfterItStillInlines() async throws {
        // Depot.Gadget spans 33 lines (over 30, under 40): no source, and it does not end inlining.
        let output = try await Self.decl("Gadget", source: Self.twoGadgets(31, 1))

        #expect(!output.contains("let depot1"), "\(output)")
        #expect(output.contains("let orchard1 = 0"), "\(output)")
    }

    @Test
    func rowsTotallingExactlyTheAnswerCapAllInline() async throws {
        // Two 20-line Gadgets make 40 lines, the cap itself.
        let output = try await Self.decl("Gadget", source: Self.twoGadgets(18, 18))
        let numbered = output.components(separatedBy: "\n").filter { $0.range(of: #"^ *\d+\t"#, options: .regularExpression) != nil }

        #expect(numbered.count == 40, "\(numbered.count) numbered lines\n\(output)")
        #expect(output.contains("let depot18"), "\(output)")
        #expect(output.contains("let orchard18"), "\(output)")
    }

    @Test
    func aRowWhoseFileNowEndsBeforeItIsSkippedAndTheNextRowInlines() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("// header\n\nstruct Gadget {\n    let stale = 0\n}\n", to: "Sources/App/A.swift", in: root)
        try TestSources.write("struct Gadget { let fresh = 0 }\n", to: "Sources/App/Z.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let engine = try SiftEngine(directory: root)
        let freshness = try await engine.ensureFresh()
        try TestSources.write("// header\n", to: "Sources/App/A.swift", in: root)
        let output = try await engine.lookup(symbol: "Gadget", freshness: freshness, options: WhereOptions(declarationsOnly: true))

        #expect(output.contains("declarations (2):"), "\(output)")
        #expect(!output.contains("let stale"), "\(output)")
        #expect(output.contains("     1\tstruct Gadget { let fresh = 0 }"), "\(output)")
    }

    @Test
    func aCarriageReturnEndingAFileLineIsNotPrinted() async throws {
        let output = try await Self.decl("Orchard", source: Self.orchard.replacingOccurrences(of: "\n", with: "\r\n"))

        #expect(output.contains("     3\tenum Orchard: String {\n"), "\(output)")
        #expect(!output.contains("\r"), "\(output)")
    }

    // MARK: At a revision

    @Test
    func anAnswerAtARevisionInlinesThatRevisionsTextNotTheWorkingTrees() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.orchard, to: "Sources/App/Orchard.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write(Self.orchard.replacingOccurrences(of: "case plum", with: "case quince"), to: "Sources/App/Orchard.swift", in: root)
        let output = try await SiftEngine(directory: root).lookup(symbol: "Orchard", at: "HEAD", options: WhereOptions(declarationsOnly: true))

        #expect(output.contains("     6\t    case plum"), "\(output)")
        #expect(!output.contains("quince"), "\(output)")
    }

    @Test
    func aPlainAnswerAtARevisionLabelsAnElseRowWithItsCondition() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("#if os(iOS)\nstruct Gizmo { let a = 0 }\n#else\nstruct Gizmo { let b = 0 }\n#endif\n", to: "Sources/App/Gizmo.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let output = try await SiftEngine(directory: root).lookup(symbol: "Gizmo", at: "HEAD")

        #expect(output.contains("[#else of #if os(iOS)]"), "\(output)")
    }
}
