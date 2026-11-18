//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `strings` reading a `|` query as any of its terms, only after the query as written finds nothing.
@Suite(.temporaryDirectories)
struct StringsAnyOfTests {
    private static func makeRepo(files: [String: String]) throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        for (path, contents) in files {
            try TestSources.write(contents, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "any-of fixture")
        return try SiftEngine(directory: root)
    }

    private static var header: String {
        "no literal contains \"alpha|beta|gamma\" as written; read as any of alpha, beta, gamma"
    }

    @Test
    func aPipeQueryThatFindsNothingAsWrittenIsReadAsAnyOfItsTerms() throws {
        let engine = try Self.makeRepo(files: [
            "Sources/Depot/One.swift": "let one = \"alpha\"\n",
            "Sources/Depot/Two.swift": "let two = \"beta\"\n",
            "Sources/Depot/Three.swift": "let three = \"gamma\"\n",
        ])

        let output = try engine.strings(query: "alpha|beta|gamma")

        #expect(output.contains(Self.header))
        #expect(output.contains("Sources/Depot/One.swift:1"))
        #expect(output.contains("Sources/Depot/Two.swift:1"))
        #expect(output.contains("Sources/Depot/Three.swift:1"))
        #expect(!output.contains("no Swift string literal contains it either"))
    }

    @Test
    func aLiteralHoldingThePipeIsAnsweredAsWritten() throws {
        let engine = try Self.makeRepo(files: [
            "Sources/Depot/One.swift": "let one = \"Save | Cancel\"\nlet two = \"Save\"\n",
        ])

        let output = try engine.strings(query: "Save | Cancel")

        #expect(output.contains("Sources/Depot/One.swift:1"))
        #expect(!output.contains("read as any of"))
    }

    @Test
    func aTermThatMatchesAndOneThatDoesNotEachGetTheirSection() throws {
        let engine = try Self.makeRepo(files: ["Sources/Depot/One.swift": "let one = \"alpha\"\n"])

        let output = try engine.strings(query: "alpha|beta")

        #expect(output.contains("read as any of alpha, beta"))
        let sections = output.components(separatedBy: "term \"beta\":")
        #expect(sections.count == 2)
        #expect(sections[0].contains("Sources/Depot/One.swift:1"))
        #expect(sections[1].contains("no Swift string literal contains it either"))
        #expect(!sections[1].contains("One.swift"))
    }

    @Test
    func termsAreTrimmedBeforeTheyAreSearchedAndNamed() throws {
        let engine = try Self.makeRepo(files: [
            "Sources/Depot/One.swift": "let one = \"Save\"\n",
            "Sources/Depot/Two.swift": "let two = \"Cancel\"\n",
        ])

        let output = try engine.strings(query: "Save | Cancel")

        #expect(output.contains("read as any of Save, Cancel"))
        #expect(output.contains("Sources/Depot/One.swift:1"))
        #expect(output.contains("Sources/Depot/Two.swift:1"))
    }
}
