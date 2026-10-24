//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// With a fresh store, a property wrapper's `@T` sites the store records no call at are listed by name beside its answer, so "no callers" is never said of a wrapper written on a function's parameter.
@Suite(.temporaryDirectories)
struct WhereStoreWrapperSitesTests {
    /// The heading every name-matched block opens with.
    static var heading: String {
        "syntactic call sites — by written name"
    }

    static var clamp: String {
        """
        @propertyWrapper struct Clamp { var wrappedValue: Int; init(wrappedValue: Int) { self.wrappedValue = wrappedValue } }
        func clamped(@Clamp _ x: Int) -> Int { x }
        let y = clamped(3)
        struct Holder {
            @Clamp var z = 1
        }
        struct Plain { let v: Int; init(v: Int) { self.v = v } }
        """
    }

    /// Three wrappers named `Clamp`: this module's, with two initializers, one nested in a type of it, and another module's, each written on a parameter the store records no call at.
    static var sameNamed: [String: String] {
        [
            "Sources/Other/Clamp.swift": """
            @propertyWrapper public struct Clamp { public var wrappedValue: Int; public init(wrappedValue: Int) { self.wrappedValue = wrappedValue } }
            public func other(@Clamp _ x: Int) -> Int { x }
            """,
            "Sources/Probe/Clamp.swift": """
            @propertyWrapper struct Clamp {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                init(wrappedValue: Int, _ cap: Int) { self.wrappedValue = min(wrappedValue, cap) }
            }
            func clamped(@Clamp _ x: Int) -> Int { x }
            func ranged(@Clamp(5) _ x: Int) -> Int { x }
            let y = clamped(3) + ranged(9)
            struct Holder {
                @Clamp var z = 1
            }
            nonisolated(unsafe) let scale = { (@Clamp x: Int) in x }
            struct Outer {
                @propertyWrapper struct Clamp { var wrappedValue: Int; init(wrappedValue: Int) { self.wrappedValue = wrappedValue } }
                @Clamp var inner = 2
                static func s(@Clamp _ x: Int) -> Int { x }
            }
            """,
        ]
    }

    /// A committed git repo holding a package of `targets` with `files`.
    static func repo(_ files: [String: String], targets: [String] = ["Probe"]) throws -> URL {
        let root = try TestSources.makeTempRepo()
        let declared = targets.map { ".target(name: \"\($0)\")" }.joined(separator: ", ")
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(name: "Probe", targets: [\(declared)])
            """,
            to: "Package.swift",
            in: root
        )
        for (path, text) in files {
            try TestSources.write(text, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "buildable fixture")
        return root
    }

    /// The `where` answer for each of `symbols` over `root`, built so its store is fresh.
    static func lookup(_ symbols: [String], in root: URL) async throws -> [String] {
        try await TestSources.swiftBuild(packageAt: root)
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()
        var answers: [String] = []
        for symbol in symbols {
            let freshness = try await engine.ensureFresh()
            try await answers.append(engine.lookup(symbol: symbol, freshness: freshness))
        }
        return answers
    }

    /// The `where` answer for `symbol` over a built package holding `source`, once its store is fresh.
    static func lookup(_ symbol: String, source: String) async throws -> String {
        let root = try repo(["Sources/Probe/Clamp.swift": source])
        return try await lookup([symbol], in: root)[0]
    }

    /// How many times `text` appears in `output`.
    static func count(of text: String, in output: String) -> Int {
        output.components(separatedBy: text).count - 1
    }

    /// A wrapper written on a function's parameter is a call the store does not record, so it is listed by name and the answer does not say "no callers".
    @Test
    func aWrapperOnAParameterIsListedBesideAFreshStore() async throws {
        let source = Self.clamp.replacingOccurrences(of: "    @Clamp var z = 1\n", with: "    var z = 1\n")
        let output = try await Self.lookup("Clamp.init", source: source)

        #expect(output.contains("semantic: fresh"), "\(output)")
        #expect(!output.contains("no callers"), "\(output)")
        #expect(output.contains(Self.heading), "\(output)")
        #expect(output.contains("\"@Clamp\" (1 call site by written name in 1 file — for init(wrappedValue:)):"), "\(output)")
        #expect(WhereAnswerRepetitionTests.sitesOnePerLine(output).split(separator: "\n").contains("  Sources/Probe/Clamp.swift:2  in clamped(_:)"), "\(output)")
        // The block is read back as name-matched, never as a resolved caller.
        #expect(!NameMatchedSites.linesOutside(answer: output).contains { $0.contains("Clamp.swift:2") }, "\(output)")
    }

    /// A wrapper on a stored property is a call the store records, so it is listed once, as the store's, and not again by name.
    @Test
    func aStoredPropertysWrapperTheStoreRecordsIsNotListedTwice() async throws {
        let output = try await Self.lookup("Clamp.init", source: Self.clamp)

        #expect(output.contains("callers of Probe.Clamp.init(wrappedValue:) (1):"), "\(output)")
        #expect(output.split(separator: "\n").contains("    :5  z  | @Clamp var z = 1"), "\(output)")
        #expect(WhereAnswerRepetitionTests.sitesOnePerLine(output).split(separator: "\n").contains("  Sources/Probe/Clamp.swift:2  in clamped(_:)"), "\(output)")
        #expect(WhereStoreSiteTextTests.located(output).components(separatedBy: "Clamp.swift:5").count == 2, "\(output)")
    }

    /// A wrapper on its own line above the stored property it wraps is recorded by the store at the attribute's own line, the same line the name scan finds it at, so it is still listed once, not twice.
    @Test
    func aWrapperWrittenOnItsOwnLineAboveTheStoredPropertyIsNotListedTwice() async throws {
        let source = Self.clamp.replacingOccurrences(of: "    @Clamp var z = 1\n", with: "    @Clamp\n    var z = 1\n")
        let output = try await Self.lookup("Clamp.init", source: source)

        #expect(output.contains("callers of Probe.Clamp.init(wrappedValue:) (1):"), "\(output)")
        #expect(output.split(separator: "\n").contains("    :5  z  | @Clamp"), "\(output)")
        #expect(WhereStoreSiteTextTests.located(output).components(separatedBy: "Clamp.swift:5").count == 2, "\(output)")
    }

    /// An initializer of a type that is no property wrapper keeps the store's answer alone, its empty case included.
    @Test
    func aTypeThatIsNoWrapperKeepsTheStoresAnswer() async throws {
        let output = try await Self.lookup("Plain.init", source: Self.clamp)

        #expect(output.contains("semantic: fresh"), "\(output)")
        #expect(output.contains("no callers of Probe.Plain.init(v:) recorded in the store"), "\(output)")
        #expect(!output.contains("syntactic call sites"), "\(output)")
    }

    /// Same-named wrapper types never lend each other their sites: each type's answer lists only the attributes the store records a reference to that type at, so another module's `Clamp` or one nested in a type is never listed for this one.
    @Test
    func sameNamedWrapperTypesListOnlyTheirOwnSites() async throws {
        let root = try Self.repo(Self.sameNamed, targets: ["Other", "Probe"])
        let answers = try await Self.lookup(["Probe.Clamp.init", "Outer.Clamp.init", "Other.Clamp.init"], in: root)
        let (probe, outer, other) = (answers[0], answers[1], answers[2])

        #expect(WhereAnswerRepetitionTests.sitesOnePerLine(probe).contains("Sources/Probe/Clamp.swift:6  in clamped(_:)"), "\(probe)")
        #expect(!WhereStoreSiteTextTests.located(probe).contains("Clamp.swift:16"), "\(probe)")
        #expect(!probe.contains("Sources/Other/"), "\(probe)")

        #expect(outer.contains("callers of Probe.Outer.Clamp.init(wrappedValue:) (1):"), "\(outer)")
        #expect(WhereAnswerRepetitionTests.sitesOnePerLine(outer).split(separator: "\n").contains("  Sources/Probe/Clamp.swift:16  in Outer.s(_:)"), "\(outer)")
        #expect(!WhereStoreSiteTextTests.located(outer).contains("Clamp.swift:6 "), "\(outer)")
        #expect(!WhereStoreSiteTextTests.located(outer).contains("Clamp.swift:7 "), "\(outer)")
        #expect(!outer.contains("Sources/Other/"), "\(outer)")

        #expect(other.contains("\"@Clamp\" (1 call site by written name in 1 file — for init(wrappedValue:)):"), "\(other)")
        #expect(WhereAnswerRepetitionTests.sitesOnePerLine(other).split(separator: "\n").contains("  Sources/Other/Clamp.swift:2  in other(_:)"), "\(other)")
        #expect(!other.contains("Sources/Probe/"), "\(other)")
    }

    /// A wrapper on a parameter is called as `init(wrappedValue:)` led by the argument, then its written labels, so each site is listed under the one initializer its labels reach and no site is listed twice.
    @Test
    func aParametersWrapperIsListedOnceUnderTheInitializerItsLabelsReach() async throws {
        let root = try Self.repo(Self.sameNamed, targets: ["Other", "Probe"])
        let output = try await Self.lookup(["Probe.Clamp.init"], in: root)[0]

        #expect(WhereAnswerRepetitionTests.sitesOnePerLine(output).contains("\"@Clamp\" (1 call site by written name in 1 file — for init(wrappedValue:)):\n  Sources/Probe/Clamp.swift:6  in clamped(_:)"), "\(output)")
        #expect(WhereAnswerRepetitionTests.sitesOnePerLine(output).contains("\"@Clamp\" (1 call site by written name in 1 file — for init(wrappedValue:_:)):\n  Sources/Probe/Clamp.swift:7  in ranged(_:)"), "\(output)")
        #expect(Self.count(of: "Clamp.swift:6  in clamped(_:)", in: WhereAnswerRepetitionTests.sitesOnePerLine(output)) == 1, "\(output)")
        #expect(Self.count(of: "Clamp.swift:7  in ranged(_:)", in: WhereAnswerRepetitionTests.sitesOnePerLine(output)) == 1, "\(output)")
    }

    /// A site whose labels reach more than one initializer is listed once, for the type, never once under each.
    @Test
    func aSiteNoOneInitializersLabelsPickOutIsListedOnceForTheType() async throws {
        let source = """
        @propertyWrapper struct Clamp {
            var wrappedValue: Int
            init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            init(wrappedValue: Int, cap: Int = 10) { self.wrappedValue = min(wrappedValue, cap) }
        }
        func clamped(@Clamp _ x: Int) -> Int { x }
        """
        let output = try await Self.lookup("Clamp.init", source: source)

        #expect(output.contains("\"@Clamp\" (1 call site by written name in 1 file — for Probe.Clamp, no one initializer by its labels):"), "\(output)")
        #expect(Self.count(of: "Clamp.swift:6  in clamped(_:)", in: WhereAnswerRepetitionTests.sitesOnePerLine(output)) == 1, "\(output)")
        #expect(!output.contains("no callers"), "\(output)")
    }

    /// A parameter attribute's first label may also be `projectedValue`, spelled where the caller passes `$x:`, so a wrapper declaring only `init(projectedValue:)` beside `init(wrappedValue:)` still finds the site, even though its labels alone cannot pick out which of the two it calls.
    @Test
    func aParametersWrapperReachesAnInitDeclaredByProjectedValue() async throws {
        let source = """
        @propertyWrapper struct PV {
            var wrappedValue: Int
            var projectedValue: PV { self }
            init(projectedValue: PV) { self.wrappedValue = projectedValue.wrappedValue }
        }
        func pv(@PV _ x: Int) {}
        """
        let output = try await Self.lookup("PV.init", source: source)

        #expect(!output.contains("no callers"), "\(output)")
        #expect(output.contains("\"@PV\" (1 call site by written name in 1 file — for init(projectedValue:)):"), "\(output)")
        #expect(Self.count(of: "Clamp.swift:6  in pv(_:)", in: WhereAnswerRepetitionTests.sitesOnePerLine(output)) == 1, "\(output)")
    }

    /// A parameter attribute's first label may also be `initialValue`, the legacy form, so a wrapper declaring only it is listed under that one initializer, since no other overload leaves its labels ambiguous.
    @Test
    func aParametersWrapperReachesAnInitDeclaredByInitialValue() async throws {
        let source = """
        @propertyWrapper struct Leg {
            var wrappedValue: Int
            init(initialValue: Int) { wrappedValue = initialValue }
        }
        func leg(@Leg _ x: Int) {}
        """
        let output = try await Self.lookup("Leg.init", source: source)

        #expect(!output.contains("no callers"), "\(output)")
        #expect(output.contains("\"@Leg\" (1 call site by written name in 1 file — for init(initialValue:)):"), "\(output)")
        #expect(Self.count(of: "Clamp.swift:5  in leg(_:)", in: WhereAnswerRepetitionTests.sitesOnePerLine(output)) == 1, "\(output)")
    }

    /// A parameter attribute written with arguments still resolves only to the one initializer whose trailing labels they match, unaffected by the `projectedValue`/`initialValue` alternatives when no such overload exists.
    @Test
    func aParametersWrittenWrapperArgumentsStillPickOnlyWrappedValue() async throws {
        let source = """
        @propertyWrapper struct Clamp {
            var wrappedValue: Int
            init(wrappedValue: Int, _ cap: Int) { self.wrappedValue = min(wrappedValue, cap) }
        }
        func clamped(@Clamp(5) _ x: Int) -> Int { x }
        """
        let output = try await Self.lookup("Clamp.init", source: source)

        #expect(!output.contains("no callers"), "\(output)")
        #expect(!output.contains("no one initializer by its labels"), "\(output)")
        #expect(output.contains("\"@Clamp\" (1 call site by written name in 1 file — for init(wrappedValue:_:)):"), "\(output)")
        #expect(Self.count(of: "Clamp.swift:5  in clamped(_:)", in: WhereAnswerRepetitionTests.sitesOnePerLine(output)) == 1, "\(output)")
    }
}
