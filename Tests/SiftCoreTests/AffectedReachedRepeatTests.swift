//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `affected --reached` repeats: the answer carries one `reached?` block per name, in the order given, and none is dropped.
@Suite(.temporaryDirectories)
struct AffectedReachedRepeatTests {
    private static func answers(probes: [[String]]) async throws -> [String] {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"Lib\",\n    targets: [\n        .target(name: \"Lib\"),\n        .testTarget(name: \"LibTests\", dependencies: [\"Lib\"]),\n    ]\n)\n", to: "Package.swift", in: root)
        try TestSources.write("public struct Widget {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        try TestSources.write("import Testing\n@testable import Lib\n\nstruct AlphaTests {\n    @Test func uses() { _ = Widget() }\n}\n", to: "Tests/LibTests/AlphaTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("public struct Widget {\n    public init() {}\n    public func shine() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        let engine = try SiftEngine(directory: root)
        try await engine.awaitSemanticStore()
        let freshness = try await engine.ensureFresh()
        var outputs: [String] = []
        for names in probes {
            try await outputs.append(engine.affected(options: AffectedOptions(probes: names), freshness: freshness))
        }
        return outputs
    }

    private static func blocks(in answer: String) -> [String] {
        answer.split(separator: "\n").filter { $0.hasPrefix("reached? ") }.map { String($0.prefix { $0 != "—" }.dropLast()) }
    }

    /// Every name gets its block, in the order given, and a name given twice gets one.
    @Test
    func eachNameGetsABlockInTheOrderGiven() async throws {
        let outputs = try await Self.answers(probes: [
            ["LibTests.GizmoTests", "LibTests.AlphaTests/uses()", "LibTests.BetaTests"],
            ["LibTests.GizmoTests", "LibTests.GizmoTests"],
        ])

        #expect(Self.blocks(in: outputs[0]) == ["reached? LibTests.GizmoTests", "reached? LibTests.AlphaTests/uses()", "reached? LibTests.BetaTests"])
        #expect(Self.blocks(in: outputs[1]) == ["reached? LibTests.GizmoTests"])
    }

    /// One name prints what it always did, byte for byte after the header line, which names the temporary repository: the text was taken from the answer the code gave before names could repeat.
    @Test
    func aSingleNameAnswersAsItAlwaysDid() async throws {
        let outputs = try await Self.answers(probes: [["LibTests.GizmoTests"]])

        let single = try #require(outputs[0].split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).last)

        // The commands in the note name the temporary repository (`--root <path>`), the one part that differs per run.
        #expect(String(single).replacingOccurrences(of: #"--root \S+ "#, with: "", options: .regularExpression) == Self.singleNameAnswer)
    }

    /// Names that nothing reached share one caveat, printed once after the last of them.
    @Test
    func theUnreachedCaveatPrintsOnceForManyNames() async throws {
        let outputs = try await Self.answers(probes: [["LibTests.GizmoTests", "LibTests.BetaTests", "LibTests.BackorderTests"]])
        let caveat = "that is not evidence that it is unaffected"
        let lines = outputs[0].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(lines.filter { $0.contains(caveat) }.count == 1)
        #expect(lines.last?.contains(caveat) == true)
        #expect(Self.blocks(in: outputs[0]).count == 3)
    }

    /// The caveat follows the last unreached block, not the end of the answer: a reached name after it still comes last.
    @Test
    func theUnreachedCaveatFollowsTheLastUnreachedBlock() async throws {
        let outputs = try await Self.answers(probes: [["LibTests.GizmoTests", "LibTests.AlphaTests"]])
        let caveat = "that is not evidence that it is unaffected"
        let lines = outputs[0].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let unreached = try #require(lines.firstIndex { $0.hasPrefix("reached? LibTests.GizmoTests") })
        let reached = try #require(lines.firstIndex { $0.hasPrefix("reached? LibTests.AlphaTests") })

        #expect(lines.filter { $0.contains(caveat) }.count == 1)
        #expect(lines[unreached + 1].contains(caveat))
        #expect(reached > unreached + 1)
    }
}

private extension AffectedReachedRepeatTests {
    /// The answer for the one unreached name, from the first line after the header.
    static var singleNameAnswer: String {
        #"""
        affected tests — changed: working tree vs HEAD
        mode: syntactic (swift-sure help answers); no index store for this tree yet — build one: swift-sure run -- swift build --build-tests. A store built elsewhere needs indexStorePath set in .swift-sure.json; Docs/Guide.md §7 lists where discovery looks.
        depth: 2 reference hops from the changed declarations
        resolved references: UNAVAILABLE — they come from the index store, which this query has none of; every test below is a NAME MATCH ONLY

        changed files (1), declarations resolved (1):
          Sources/Lib/Core.swift — added or modified, 1 of 3 declarations touched

        what this cannot see — read before trusting the list below: answered by a call-site walk from the declarations the diff touched (syntactic, lower bound). this is a lower bound, not a safe-to-skip set: it reports, it does not run, and it never decides what to leave out. The standing limits: `swift-sure help affected-limits`.
          · the reference walk stops at 2 hops — a test further out is not listed; `-only-testing:` names the module: a target with its own PRODUCT_MODULE_NAME makes xcodebuild fail the whole invocation rather than skipping that selection

        call-site walk — syntactic, lower bound: the 1 file changed was seeded from the 1 name the diff touched there (shine), not every declaration in it, and followed to the call sites `where` finds by written name, 2 names over every hop. **A call site found by name is not a resolved reference** — same-named members of unrelated types are included, and dynamically dispatched uses are missed. Those tests are marked `name match` below, and a test the diff touched is listed itself.

        affected tests (1 in 1 target):
          LibTests — 1 test
            LibTests.AlphaTests/uses() — 1 hop, name match — Tests/LibTests/AlphaTests.swift:5

        xcodebuild — one argument per selection; 1 of the tests these select rest on a name match rather than a resolved reference:
          -only-testing:LibTests/AlphaTests/uses()

        swift test — SwiftPM matches --filter as a regex against the printed test id:
          swift test --filter '^LibTests\.AlphaTests/uses\(\)'

        reached? LibTests.GizmoTests — not reached within 2 reference hops.
          that is not evidence that it is unaffected: the index found no reference to it, which the limits above list ways of being wrong about.
        """#
    }
}
