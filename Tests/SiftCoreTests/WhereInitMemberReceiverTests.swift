//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A `where` answer for an initializer lists the lines outside the build that write the word `init` as a member of a type, and leaves out those whose receiver is a type the index or the standard library proves is another.
@Suite(.serialized, .temporaryDirectories)
struct WhereInitMemberReceiverTests {
    private static var stray: String {
        "Fixtures/BetaTests.swift"
    }

    private static var shadowing: String {
        "Fixtures/OrchardTests.swift"
    }

    private static var late: String {
        "Sources/Lib/Late.swift"
    }

    private static var header: String {
        "@testable import Lib\nimport Testing\n\n"
    }

    /// Scanned files, each writing a receiver name another way a file can bind it, an SDK conformance or extension binding `Data` or `Range` unwritten among them; their `init` line is kept (a line number) except where a dictionary's key is the only mention, or a standard name is written outside every type declaration or, where no SDK binds it, inside one.
    private static let rebindingPins: [RebindingPin] = [
        RebindingPin(path: "Fixtures/extension-clause.swift", text: "extension Holder { func make(_ names: [String]) -> [Gadget] { names.map(Gadget.init) } }\n", line: 4),
        RebindingPin(path: "Fixtures/pack-clause.swift", text: "func pack<each Item: Base>(_ names: [String]) { _ = names.map(Item.init) }\n", line: 4),
        RebindingPin(path: "Fixtures/line-comment-clause.swift", text: "func clause<\n    // the element\n    Widget\n>(_ names: [String]) { _ = names.map(Widget.init) }\n", line: 7),
        RebindingPin(path: "Fixtures/block-comment-clause.swift", text: "func clause<A, /* the element */ Gizmo>(_ names: [A]) { _ = names.map(Gizmo.init) }\n", line: 4),
        RebindingPin(path: "Fixtures/metatype-clause.swift", text: "let Local: Base.Type = Sub.self\n_ = names.map(Local.init)\n", line: 5),
        RebindingPin(path: "Fixtures/parameter-clause.swift", text: "func take(_ Other: Base.Type, _ names: [String]) { _ = names.map(Other.init) }\n", line: 4),
        RebindingPin(path: "Fixtures/for-in-clause.swift", text: "for Local in [Sub.self] as [Base.Type] { _ = names.map(Local.init) }\n", line: 4),
        RebindingPin(path: "Fixtures/closure-clause.swift", text: "let make: (Base.Type, [String]) -> [Base] = { Item, names in names.map(Item.init) }\n", line: 4),
        RebindingPin(path: "Fixtures/same-type-clause.swift", text: "extension Array where Element == Sub { static func make(_ names: [String]) -> [Element] { names.map(Element.init) } }\n", line: 4),
        RebindingPin(path: "Fixtures/dictionary-clause.swift", text: "let counts: [String: Int] = [:]\n_ = names.map(String.init)\n", line: nil),
        RebindingPin(path: "Fixtures/dynamic-view-content-clause.swift", text: "struct CrateSet: DynamicViewContent {\n    var data: [Sub]\n    func fresh(_ names: [String]) -> [Base] { names.map(Data.init) }\n}\n", line: 6),
        RebindingPin(path: "Fixtures/range-subscript-clause.swift", text: "extension CollectionRangeSubscript { func make(_ names: [String]) -> [Base] { names.map(Range.init) } }\n", line: 4),
        RebindingPin(path: "Fixtures/top-level-data-clause.swift", text: "_ = names.map(Data.init)\n_ = names.map(Range.init)\n", line: nil),
        RebindingPin(path: "Fixtures/type-string-clause.swift", text: "struct Names {\n    func make(_ names: [String]) -> [String] { names.map(String.init) }\n}\n", line: nil),
    ]

    /// The line numbers listed for `path` on the mention line that opens with `heading`, or none.
    private static func listed(_ path: String, under heading: String, in answer: String) -> [Int] {
        let compact = MentionRows.compacted(answer)
        guard let line = compact.split(separator: "\n").first(where: { $0.contains(heading) }), let range = line.range(of: heading) else { return [] }
        let entries = line[range.upperBound...].components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let entry = entries.first(where: { $0.hasPrefix(path + ":") }) else { return [] }
        return entry.dropFirst(path.count + 1).split(separator: ",").compactMap { Int($0) }
    }

    /// An unapplied `String.init` or another struct's `.init` is no reference to a struct's initializer, nor to a class's where the receiver is a struct; `Self`, an alias, a leading dot and a subclass of the class stay, and a file that changed since the build is read the same way.
    @Test
    func anotherTypesUnappliedInitIsNotListedAsAMention() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(
            """
            // swift-tools-version:5.9
            import PackageDescription

            let package = Package(
                name: "Lib",
                targets: [.target(name: "Lib"), .testTarget(name: "LibTests", dependencies: ["Lib"])]
            )
            """,
            to: "Package.swift",
            in: root
        )
        try TestSources.write(
            """
            public struct Gizmo {
                public init(label: String) {}
            }

            public struct Widget {
                public init(label: String) {}
            }

            public typealias Alias = Gizmo

            open class Base {
                public init(label: String) {}
            }

            public final class Sub: Base {}

            open class Mid: Base {}

            public final class Leaf: Mid {}

            public final class Other {
                public init(label: String) {}
            }

            public struct Item {}

            public struct Gadget {}

            public struct Local {}

            public struct Element {}

            public struct Holder<Gadget: Base> {}
            """,
            to: "Sources/Lib/Types.swift",
            in: root
        )
        try TestSources.write("@testable import Lib\nimport Testing\n\n@Test func reads() {\n    _ = Gizmo(label: \"a\")\n}\n", to: "Tests/LibTests/GadgetTests.swift", in: root)
        try TestSources.write(
            """
            @testable import Lib
            import Testing

            @Test func strays() {
                let names = ["a"]
                _ = names.map(String.init)
                _ = names.map(Widget.init)
                _ = names.map(Gizmo.init)
                _ = names.map(Alias.init)
                _ = names.map(.init)
                _ = names.map(Sub.init)
            }

            extension Gizmo {
                static func many(_ names: [String]) -> [Gizmo] { names.map(Self.init) }
            }

            func more(_ names: [String]) {
                _ = names.map(Other.init)
                _ = names.map(Leaf.init)
                _ = names.map(Item.init)
            }
            """,
            to: Self.stray,
            in: root
        )
        try TestSources.write(
            """
            @testable import Lib
            import Testing

            func generic<Item: Base>(_ names: [String]) -> [Item] { names.map(Item.init) }
            struct Holder<Gadget: Base> {
                func make(_ names: [String]) -> [Gadget] { names.map(Gadget.init) }
            }
            func local(_ names: [String]) -> [Base] {
                class Local: Base {}
                return names.map(Local.init)
            }

            @Test func shadows() {}
            """,
            to: Self.shadowing,
            in: root
        )
        for pin in Self.rebindingPins {
            try TestSources.write(Self.header + pin.text, to: pin.path, in: root)
        }
        try TestSources.commitAll(in: root, message: "seed")
        try await TestSources.swiftBuildSuspending(packageAt: root, includingTests: true)

        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        engine.callerDirectory = engine.repoRoot.path
        try await engine.awaitSemanticStore()
        _ = try await engine.ensureFresh()
        try TestSources.write("func late(_ names: [String]) {\n    _ = names.map(String.init)\n    _ = names.map(Gizmo.init)\n}\n", to: Self.late, in: root)
        let freshness = try await engine.ensureFresh()

        let gizmo = try await engine.lookup(symbol: "Gizmo.init(label:)", freshness: freshness)
        let base = try await engine.lookup(symbol: "Base.init(label:)", freshness: freshness)
        let unbuilt = "not in the build, mention the name:"
        let newSince = "new since last build, not in the store, mention the name:"

        #expect(Self.listed(Self.stray, under: unbuilt, in: gizmo) == [8, 9, 10, 11, 15, 19, 20], "\(gizmo)")
        #expect(Self.listed(Self.stray, under: unbuilt, in: base) == [9, 10, 11, 15, 20], "\(base)")
        #expect(Self.listed(Self.shadowing, under: unbuilt, in: base) == [4, 6, 9, 10], "\(base)")
        #expect(Self.listed(Self.shadowing, under: unbuilt, in: gizmo) == [4, 6, 10], "\(gizmo)")
        #expect(Self.listed(Self.late, under: newSince, in: gizmo) == [3], "\(gizmo)")
        for pin in Self.rebindingPins {
            #expect(Self.listed(pin.path, under: unbuilt, in: base) == pin.line.map { [$0] } ?? [], "\(pin.path): \(base)")
        }
    }

    /// Where two initializers of different types share a name, a receiver ruled out for only one of them stays in the scan: the rulings intersect, so `Widget.init` is a hit for the pair though it is ruled out for `Gizmo` alone, and `String.init` is dropped for both.
    @Test
    func aReceiverRuledOutForOnlyOneOfTwoInitializersStaysInTheScan() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("struct Gizmo {\n    init(label: String) {}\n}\n\nstruct Widget {\n    init(label: String) {}\n}\n", to: "Sources/Lib/Types.swift", in: root)
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)
        try await engine.ensureFresh()
        let inits = try engine.store.symbols(named: "init(label:)")
        let owners = try inits.map { try $0.parentID.flatMap { try engine.store.symbol(withID: $0) }?.name }
        let gizmo = zip(inits, owners).filter { $0.1 == "Gizmo" }.map(\.0)
        let widget = zip(inits, owners).filter { $0.1 == "Widget" }.map(\.0)
        let source = Array("_ = names.map(Widget.init)\n_ = names.map(String.init)\n_ = names.map(Gizmo.init)\n".utf8)
        let both = try ScannedNames(rows: gizmo + widget, in: engine.store)
        let alone = try ScannedNames(rows: gizmo, in: engine.store)

        let pair = source.withUnsafeBytes { both.hits(of: "init", in: $0).map(\.line) }
        let single = source.withUnsafeBytes { alone.hits(of: "init", in: $0).map(\.line) }

        #expect(!gizmo.isEmpty && !widget.isEmpty)
        #expect(pair == [1, 3])
        #expect(single == [3])
    }
}

extension WhereInitMemberReceiverTests {
    struct RebindingPin {
        let path: String
        let text: String
        let line: Int?
    }
}

extension WhereInitMemberReceiverTests {
    /// Scanned files each writing an unapplied `.init` of a receiver the index declares as another type, with the lines a scan for `Gizmo`'s initializer keeps.
    private static let enclosurePins: [(text: String, lines: [Int])] = [
        ("extension Q { func f(_ n: [String]) -> [Element] { n.map(Element.init) } }\n", [1]),
        ("extension [Gizmo] { func f(_ n: [String]) -> [Element] { n.map(Element.init) } }\n", [1]),
        ("extension Optional<Gizmo> { func f(_ n: [String]) -> [Wrapped] { n.map(Wrapped.init) } }\n", [1]),
        ("struct Bag: Sequence {\n    func makeIterator() -> IndexingIterator<[Gizmo]> { [Gizmo]().makeIterator() }\n    func f(_ n: [String]) -> [Element] { n.map(Element.init) }\n}\n", [3]),
        ("let f = { [Element = Gizmo.self] (n: [String]) in n.map(Element.init) }\n", [1]),
        ("extension Array where Gizmo == Element { func f(_ n: [String]) -> [Element] { n.map(Element.init) } }\n", [1]),
        ("let `Element` = Gizmo.self\n_ = names.map(`Element`.init)\n", [2]),
        ("struct Box {\n    func f(_ n: [String]) -> [String] { n.map(String.init) }\n}\n", []),
        ("struct Rows: DynamicViewContent {\n    func f(_ n: [String]) -> [Data] { n.map(Data.init) }\n}\n", [2]),
        ("_ = names.map(Data.init)\n", []),
        ("_ = names.map(Wrapped.init)\n", []),
        ("_ = names.map(`Wrapped`.init)\n", []),
        ("func g(_ n: [String]) {\n    _ = n.map(Wrapped.init)\n}\n", []),
        ("let make: ([String]) -> [Wrapped] = { $0.map(Wrapped.init) }\n", []),
        ("func g(_ n: [String]) { _ = n.map(Wrapped.init) }\nstruct Box { func f(_ n: [String]) -> [Wrapped] { n.map(Wrapped.init) } }\n", [2]),
    ]

    /// A type the index declares under another name is ruled out only at a use outside every type, extension and protocol declaration of the scanned file, since inside one a conformance or a generic extension can bind an associated type of that name unwritten; a standard name no SDK binds stays ruled out inside one, one an SDK binds (`Data`) does not, and a backticked receiver is read as its bare name.
    @Test
    func anIndexDeclaredReceiverIsKeptInsideATypeDeclaration() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("struct Gizmo {\n    init(label: String) {}\n}\n\nenum Menu {\n    struct Element {}\n}\n\nstruct Wrapped {}\n", to: "Sources/Lib/Types.swift", in: root)
        try TestSources.write("protocol Q: Collection where Element == Gizmo {}\n", to: "Sources/Lib/Q.swift", in: root)
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)
        try await engine.ensureFresh()
        let inits = try engine.store.symbols(named: "init(label:)")
        let names = try ScannedNames(rows: inits, in: engine.store)

        #expect(inits.count == 1)
        for pin in Self.enclosurePins {
            let lines = Array(pin.text.utf8).withUnsafeBytes { names.hits(of: "init", in: $0).map(\.line) }
            #expect(lines == pin.lines, "\(pin.text)")
        }
    }
}
