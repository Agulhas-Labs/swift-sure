//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `allCases` in the line that ends a type digest: the compiler synthesizes it only for an enum no case of which has associated values.
@Suite(.temporaryDirectories)
struct DigestSynthesizedAllCasesTests {
    /// Enough members, with bodies, that the digest is served rather than the source.
    private static let padding = (1 ... 24).map { index in
        """
            func step\(index)(input: Int) -> Int {
                let doubled = input * 2
                let shifted = doubled + \(index)
                return shifted - input
            }
        """
    }.joined(separator: "\n\n")

    private static func noteLine(_ declaration: String) throws -> String? {
        let store = try TestSources.makeStore()
        let root = try TestSources.makeTempDirectory()
        let source = "\(declaration)\n" + padding + "\n}\n"
        try store.replaceFiles([TestSources.parsed(source, path: "Sources/Core/File0.swift", in: root)]) { _ in ("Core", false) }
        let renderer = try DigestRenderer(store: store, moduleNames: store.moduleNames(), repoRoot: root)
        let output = try renderer.render(target: "Gizmo", options: DigestOptions())
        return output.split(separator: "\n").map(String.init).last { $0.hasPrefix("synthesized members") }
    }

    @Test(arguments: [
        "enum Gizmo: CaseIterable {\n    case a(Int)\n",
        "enum Gizmo: CaseIterable {\n    case a(x: Int)\n",
        "enum Gizmo: CaseIterable {\n    case a, b(String)\n",
    ])
    func enumWithAssociatedValuesIsNotToldAllCasesIsSynthesized(_ declaration: String) throws {
        #expect(try Self.noteLine(declaration) == nil)
    }

    @Test
    func enumOfPlainCasesStillNamesAllCases() throws {
        let line = try Self.noteLine("enum Gizmo: CaseIterable {\n    case a, b\n")

        #expect(line == "synthesized members (allCases) not listed")
    }
}
