//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Pins that a walk-on which could not expand a declaration, because its file was edited since the build, says so instead of reading as a file with no references.
struct AffectedWalkOnUnansweredTests {
    private static func row(_ id: Int64, _ path: String) -> SymbolRow {
        SymbolRow(
            id: id, fileID: id, path: path, module: "Lib", parentID: nil, kind: .function, name: "f\(id)()",
            line: 1, column: 1, endLine: 2, accessLevel: .internalLevel, isStatic: false, isStored: false,
            signature: "func f\(id)()", docSummary: nil, ifConfigCondition: nil, viewOutline: nil
        )
    }

    /// Two files whose walk-on declarations the store cannot answer for: both reach none, and the note names them in order.
    @Test
    func filesTheExpansionCouldNotAnswerForAreNamed() throws {
        var roots: [String: [SymbolRow]] = [:]
        var hits: [Int64: [ResolvedWalkOn.Hit]] = [:]
        for (index, path) in ["b.swift", "a.swift"].enumerated() {
            let root = Self.row(Int64(index + 1), path)
            roots[path] = [root]
            hits[root.id] = [ResolvedWalkOn.Hit(enclosing: Self.row(Int64(index + 11), path), test: nil, state: .live, leadsOn: true)]
        }
        var walkOn = ResolvedWalkOn(hits: hits) { _ in nil }
        var budget = 10

        let result = try walkOn.run(from: roots, depth: 1, budget: &budget)

        #expect(result.unanswered == ["a.swift", "b.swift"])
        #expect(result.unansweredNote == "note: the walk-on could not follow declarations in 2 files edited since the build (a.swift, b.swift), so a file above that reached none may reach a test through them")
    }

    /// An expansion that answers, even with nothing, leaves no note.
    @Test
    func anAnsweredExpansionLeavesNoNote() throws {
        let root = Self.row(1, "a.swift")
        let hit = ResolvedWalkOn.Hit(enclosing: Self.row(11, "a.swift"), test: nil, state: .live, leadsOn: true)
        var walkOn = ResolvedWalkOn(hits: [1: [hit]]) { _ in [] }
        var budget = 10

        let result = try walkOn.run(from: ["a.swift": [root]], depth: 1, budget: &budget)

        #expect(result.unansweredNote == nil)
    }
}
