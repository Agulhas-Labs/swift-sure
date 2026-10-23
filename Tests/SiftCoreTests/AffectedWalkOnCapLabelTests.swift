//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Pins the label a capped walk-on file carries: it says how far the walk got, not that the file was not walked.
struct AffectedWalkOnCapLabelTests {
    private static func row(_ id: Int64, _ path: String) -> SymbolRow {
        SymbolRow(
            id: id, fileID: id, path: path, module: "Lib", parentID: nil, kind: .function, name: "f\(id)()",
            line: 1, column: 1, endLine: 2, accessLevel: .internalLevel, isStatic: false, isStored: false,
            signature: "func f\(id)()", docSummary: nil, ifConfigCondition: nil, viewOutline: nil
        )
    }

    /// A chain with room to expand one declaration past the bound: the walk goes one hop past it and the cap stops it there.
    @Test
    func aCappedFileSaysHowManyHopsItWasWalked() throws {
        let root = Self.row(1, "a.swift")
        let hit = ResolvedWalkOn.Hit(enclosing: Self.row(11, "a.swift"), test: nil, state: .live, leadsOn: true)
        let next = ResolvedWalkOn.Hit(enclosing: Self.row(12, "a.swift"), test: nil, state: .live, leadsOn: true)
        var walkOn = ResolvedWalkOn(hits: [1: [hit]]) { _ in [next] }
        var budget = 1

        let result = try walkOn.run(from: ["a.swift": [root]], depth: 1, budget: &budget)

        #expect(result.outcomes.first?.described == "a.swift cut short by the cap (walked 2 hops)")
        #expect(result.capNote(cap: 5)?.contains("`cut short by the cap` above were walked only as far as each says") == true)
    }
}
