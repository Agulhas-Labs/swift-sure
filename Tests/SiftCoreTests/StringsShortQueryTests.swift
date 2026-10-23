//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `strings` with a query of three characters or fewer, which matches whole words only: `OK` is not found inside "Woke up".
@Suite(.temporaryDirectories)
struct StringsShortQueryTests {
    private static func makeRepo(files: [String: String]) throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        for (path, contents) in files {
            try TestSources.write(contents, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "short query fixture")
        return try SiftEngine(directory: root)
    }

    private static func entry(_ key: String, _ value: String) -> String {
        "\"\(key)\": {\"localizations\": {\"en\": {\"stringUnit\": {\"state\": \"translated\", \"value\": \"\(value)\"}}}}"
    }

    private static var catalog: String {
        let entries = [
            entry("gizmo.ok", "OK"),
            entry("gizmo.cancelled", "Not OK"),
            entry("gizmo.strokes", "Swimming Strokes"),
            entry("gizmo.woke", "Woke up"),
        ].joined(separator: ",\n")
        return "{\"sourceLanguage\": \"en\", \"strings\": {\n\(entries)\n}, \"version\": \"1.0\"}"
    }

    @Test
    func aShortQueryListsWholeWordValuesInACatalog() throws {
        let engine = try Self.makeRepo(files: ["Resources/Localizable.xcstrings": Self.catalog])

        let output = try engine.strings(query: "OK")

        #expect(output.contains("gizmo.ok"))
        #expect(output.contains("gizmo.cancelled"))
        #expect(!output.contains("Swimming Strokes"))
        #expect(!output.contains("Woke up"))
    }

    @Test
    func aShortQueryListsWholeWordValuesInALegacyStringsFile() throws {
        let engine = try Self.makeRepo(files: [
            "en.lproj/Gizmo.strings":
                """
                "gizmo.ok" = "OK";
                "gizmo.cancelled" = "Not OK";
                "gizmo.strokes" = "Swimming Strokes";
                "gizmo.woke" = "Woke up";
                """,
        ])

        let output = try engine.strings(query: "OK")

        #expect(output.contains("gizmo.ok"))
        #expect(output.contains("gizmo.cancelled"))
        #expect(!output.contains("gizmo.strokes"))
        #expect(!output.contains("gizmo.woke"))
    }

    @Test
    func aKeyWithTheQueryBetweenNonLettersMatches() throws {
        let engine = try Self.makeRepo(files: [
            "Resources/Localizable.xcstrings":
                "{\"sourceLanguage\": \"en\", \"strings\": {\(Self.entry("OK_BUTTON", "Confirm")), \(Self.entry("OKAY_BUTTON", "Fine"))}, \"version\": \"1.0\"}",
        ])

        let output = try engine.strings(query: "OK")

        #expect(output.contains("OK_BUTTON"))
        #expect(!output.contains("OKAY_BUTTON"))
    }

    @Test
    func aFourCharacterQueryStillMatchesInsideWords() throws {
        let engine = try Self.makeRepo(files: ["Resources/Localizable.xcstrings": Self.catalog])

        let prefix = try engine.strings(query: "Woke")
        let inside = try engine.strings(query: "roke")

        #expect(prefix.contains("Woke up"))
        #expect(inside.contains("Swimming Strokes"))
    }

    @Test
    func aShortQueryMatchesSwiftLiteralsByWholeWordOnly() throws {
        let engine = try Self.makeRepo(files: [
            "Sources/Depot/Labels.swift":
                """
                struct Labels {
                    let rate = "Stroke rate"
                    let confirm = "OK"
                }
                """,
        ])

        let okOutput = try engine.strings(query: "OK")
        let roOutput = try engine.strings(query: "ro")

        #expect(okOutput.contains("\"OK\""))
        #expect(!okOutput.contains("Stroke rate"))
        #expect(!roOutput.contains("Stroke rate"))
    }

    @Test
    func aShortQueryReadsConcatenatedLiteralsByTheSameRule() throws {
        let engine = try Self.makeRepo(files: [
            "Sources/Depot/Labels.swift":
                """
                struct Labels {
                    let rate = "Stro" + "kes"
                    let refusal = "Not O" + "K"
                }
                """,
        ])

        let output = try engine.strings(query: "OK")

        #expect(output.contains("Not O"))
        #expect(!output.contains("Stro"))
    }

    @Test
    func aLongLiteralIsWindowedAroundTheWholeWordMatch() throws {
        let literal = "The gizmo finally woke up the neighbours, who had been asleep for hours, and the depot said OK to it"
        let engine = try Self.makeRepo(files: [
            "Sources/Depot/Labels.swift": "struct Labels {\n    let note = \"\(literal)\"\n}\n",
        ])

        let output = try engine.strings(query: "OK")

        #expect(literal.count > 80)
        #expect(output.contains("said OK to it"))
    }
}
