//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers a by-name call list dropping a trailing-closure call whose closure would have to fill a parameter of a non-function type.
@Suite(.temporaryDirectories)
struct LabelNarrowedTrailingClosureTests {
    private static func lookup(_ symbol: String, declaring declarations: String, calling calls: String) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(declarations, to: "Sources/App/Types.swift", in: root)
        try TestSources.write(calls, to: "Sources/App/Calls.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let engine = try SiftEngine(directory: root)
        let freshness = try await engine.ensureFresh()
        return try await engine.lookup(symbol: symbol, freshness: freshness)
    }

    @Test
    func aTrailingClosureCallOfAMethodTakingTwoStringsIsDropped() async throws {
        let output = try await Self.lookup(
            "Gizmo.merging",
            declaring: """
            struct Gizmo {
                func merging(_ message: String, with note: String) -> String { message }
            }
            """,
            calling: """
            struct Calls {
                let gizmo = Gizmo()
                let table = [String: Int]()
                func one() { _ = gizmo.merging(a, with: b) }
                func two() { _ = table.merging(other) { current, _ in current } }
            }
            """
        )

        #expect(output.contains("in Calls.one()"))
        #expect(!output.contains("in Calls.two()"))
    }

    /// Every type here names a closure-taking parameter in a way a trailing closure can reach, bar the one taking two strings.
    private static var reachableDeclarations: String {
        """
        typealias URL = () -> Void
        struct Gizmo {
            typealias Data = () -> Void
            func run(_ x: Gizmo.Data) {}
            func load(_ x: Data) {}
            func merging(_ message: String, with note: String) -> String { message }
        }
        struct Widget { func update(_ x: URL) {} }
        struct Box<Date> {
            func store(_ x: Date) {}
            init(_ x: Date) {}
        }
        """
    }

    private static var reachingCalls: String {
        """
        struct Calls {
            func memberType() { Gizmo().run { } }
            func three() { Gizmo().load { } }
            func four() { Widget().update { } }
            func five() { Box<() -> Void>().store { } }
            func six() { _ = Box { } }
            func plain() { _ = Gizmo().merging(a, with: b) }
            func strings(table: [String: Int]) { _ = table.merging(other) { current, _ in current } }
        }
        """
    }

    @Test(arguments: [
        ("Gizmo.run", "in Calls.memberType()"),
        ("Gizmo.load", "in Calls.three()"),
        ("Widget.update", "in Calls.four()"),
        ("Box.store", "in Calls.five()"),
        ("Box.init", "in Calls.six()"),
    ])
    func aTrailingClosureStaysWhereTheParameterTypeCouldBeAFunction(symbol: String, site: String) async throws {
        let output = try await Self.lookup(symbol, declaring: Self.reachableDeclarations, calling: Self.reachingCalls)

        let line = output.split(separator: "\n").first { $0.contains(site) }

        #expect(line != nil)
        #expect(line?.contains("no declared init matches") == false)
    }

    @Test
    func aTrailingClosureStillDropsWhereTheStringParametersAreTheStandardOnes() async throws {
        let output = try await Self.lookup("Gizmo.merging", declaring: Self.reachableDeclarations, calling: Self.reachingCalls)

        #expect(output.contains("in Calls.plain()"))
        #expect(!output.contains("in Calls.strings("))
    }

    /// A memberwise initializer is not reached by a name-matched list, so its parameters are pinned where they are read.
    @Test
    func aMemberwiseParameterIsJudgedByItsPropertyType() throws {
        let body = try #require(Self.memberwise("let body: () -> Void", name: "body"))
        let label = try #require(Self.memberwise("let name: [String]", name: "name"))
        let bare = try #require(Self.memberwise("var extra", name: "extra"))

        #expect(body.accepts(WrittenArguments(labels: [], hasTrailingClosure: true, trailingLabels: []), takesInstance: false))
        #expect(!label.accepts(WrittenArguments(labels: [], hasTrailingClosure: true, trailingLabels: []), takesInstance: false))
        #expect(bare.parameters.first?.takesClosure == true)

        let first = try #require(Self.memberwise("var action = { }, count: [Int] = []", name: "action"))
        #expect(first.parameters.first?.takesClosure == true)
    }

    /// A property is defaulted by its own binding, read from its declaration's source where the signature stops short of an initial value.
    @Test(arguments: [
        ("var a = 1, b: Int?", "a", true),
        ("var a = 1, b: Int?", "b", true),
        ("var b: Int?, c = 2", "b", true),
        ("var b: Int?, c = 2", "c", true),
        ("var a, b: Int?", "a", true),
        ("var x: Int, y: Int?", "x", false),
        ("var x: Int, y: Int?", "y", true),
        ("var a = 1, b: Int", "b", false),
        ("let a, b: Int?", "a", false),
    ])
    func aMemberwiseParameterIsDefaultedByItsOwnBinding(declaration: String, name: String, isDefaulted: Bool) throws {
        let labels = try #require(Self.memberwise("var \(name)", name: name, source: [declaration]))

        #expect(labels.parameters.first?.isDefaulted == isDefaulted)
    }

    private static func memberwise(_ signature: String, name: String, source: [String]? = nil) -> ParameterLabels? {
        let row = SymbolRow(
            id: 1, fileID: 1, path: "Sources/App/Types.swift", module: "App", parentID: nil, kind: .variable, name: name,
            line: 1, column: 1, endLine: 1, accessLevel: .internalLevel, isStatic: false, isStored: true,
            signature: signature, docSummary: nil, ifConfigCondition: nil, viewOutline: nil
        )
        return MemberwiseParameters(source: source.map { lines in { _ in lines } }).labels(of: [row])
    }
}
