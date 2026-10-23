//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The string-catalog keys `where --refs` lists under `not code`: only top-level keys of `.xcstrings`, `.strings` and `.stringsdict` files, each judged at its occurrences of the name as a match, a lead or no hit, and listed by the line it stands on.
@Suite(.temporaryDirectories)
struct NonCodeCatalogKeysTests {
    private static func scan(_ name: String, catalogs: [String: Data], swift: [String: String] = [:]) throws -> NonCodeMentions {
        let root = try TemporaryDirectory.make("catalogkeys")
        for (path, data) in catalogs {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        for (path, text) in swift {
            try TestSources.write(text, to: path, in: root)
        }
        return NonCodeMentions.scan(name: name, swiftFiles: swift.keys.sorted(), markdownFiles: [], catalogFiles: catalogs.keys.sorted(), under: root)
    }

    private static func scan(_ name: String, catalogs: [String: String]) throws -> NonCodeMentions {
        try scan(name, catalogs: catalogs.mapValues { Data($0.utf8) })
    }

    /// Each key of a one-key-per-line `.xcstrings` file, judged for `name`: `match`, `lead` or `none`.
    private static func classify(_ name: String, keys: [String]) throws -> [String: String] {
        let body = keys.map { "\"\($0)\" : { }" }.joined(separator: ",\n")
        let text = "{\n\"strings\" : {\n\(body)\n}\n}\n"
        let found = try scan(name, catalogs: ["Resources/Walk.xcstrings": text])
        let file = found.files.first
        var verdicts: [String: String] = [:]
        for (index, key) in keys.enumerated() {
            let line = file?.lines.first { $0.number == index + 3 }
            verdicts[key] = line.map { $0.isLead ? "lead" : "match" } ?? "none"
        }
        return verdicts
    }

    private static var xcstrings: String {
        """
        {
          "sourceLanguage" : "en",
          "strings" : {
            "Shop.Gizmo.Strings.partFits" : {
              "localizations" : {
                "en" : {
                  "stringUnit" : {
                    "value" : "Gizmo met"
                  }
                }
              }
            },
            "Shop.Gizmo.Strings.low": {
              "comment" : "Gizmo comment"
            },
            "Shop.Gizmo.Strings.tooTight" : {
              "localizations" : {
                "en" : {
                  "substitutions" : {
                    "Gizmo" : {
                      "argNum" : 1
                    }
                  }
                }
              }
            },
            "Other" : { }
          },
          "version" : "1.0"
        }
        """
    }

    /// The three keys derived from a reflected name are listed at their lines, whichever spacing wrote them; a substitution named for the type at depth three, a value and a comment holding it are not.
    @Test
    func topLevelKeysAreListedAtTheirLinesAndNestedOnesAreNot() throws {
        let found = try Self.scan("Gizmo", catalogs: ["Resources/Localizable.xcstrings": Self.xcstrings])
        let file = try #require(found.files.first)

        #expect(file.isCatalog)
        #expect(file.lines(of: .catalogKey) == [4, 13, 16])
        #expect(file.lines.allSatisfy { !$0.isLead })
        #expect(found.catalogsRead == 1)
        #expect(found.codeLines == 0)
    }

    /// A match sits between separators or a key's ends; a lead stands as whole camel-case words beside anything else; whitespace beside it, or a word run on, is no hit.
    @Test
    func anUppercaseNameIsMatchedLedOrLeftOutByItsNeighbours() throws {
        let verdicts = try Self.classify("Gizmo", keys: [
            "Gizmo", "Shop.Gizmo.Strings.title", "Gizmo.Strings.partFits", "Gizmo_partFits",
            "GizmoTitle", "settingsGizmo", "URLGizmo", "Gizmo2", "Gizmo-title", "Gizmo<Int>.Strings.title",
            "Open Gizmo", "Gizmos", "Nothing",
        ])

        for key in ["Gizmo", "Shop.Gizmo.Strings.title", "Gizmo.Strings.partFits", "Gizmo_partFits"] {
            #expect(verdicts[key] == "match", "\(key)")
        }
        for key in ["GizmoTitle", "settingsGizmo", "URLGizmo", "Gizmo2", "Gizmo-title", "Gizmo<Int>.Strings.title"] {
            #expect(verdicts[key] == "lead", "\(key)")
        }
        for key in ["Open Gizmo", "Gizmos", "Nothing"] {
            #expect(verdicts[key] == "none", "\(key)")
        }
    }

    /// A lowercase name is an ordinary path component in hand-written keys, so it matches only as the whole key or after an uppercase component.
    @Test
    func aLowercaseNameMatchesOnlyAsTheWholeKeyOrAfterAnUppercaseComponent() throws {
        let verdicts = try Self.classify("partFits", keys: [
            "partFits", "Gizmo.Strings.partFits", "Gizmo_partFits",
            "settings.partFits", "partFitsTitle", "partFits.title", "Ab_cd_partFits",
            "ispartFits",
        ])

        for key in ["partFits", "Gizmo.Strings.partFits", "Gizmo_partFits"] {
            #expect(verdicts[key] == "match", "\(key)")
        }
        for key in ["settings.partFits", "partFitsTitle", "partFits.title", "Ab_cd_partFits"] {
            #expect(verdicts[key] == "lead", "\(key)")
        }

        #expect(verdicts["ispartFits"] == "none")
    }

    /// A UTF-16 file of either byte order is transcoded before the name's bytes are searched for; a UTF-8 mark is dropped so a bare first key is a match; a comment holding the name is no key.
    @Test
    func encodingsAreDecodedBeforeTheSearch() throws {
        let text = "/* Gizmo */\n\"Shop.Gizmo.Title\" = \"Gizmo\";\n"
        var little = Data([0xFF, 0xFE])
        try little.append(#require(text.data(using: .utf16LittleEndian)))
        var big = Data([0xFE, 0xFF])
        try big.append(#require(text.data(using: .utf16BigEndian)))
        var bare = Data([0xEF, 0xBB, 0xBF])
        bare.append(Data("Gizmo = \"x\";\n/* Gizmo */\n".utf8))

        let found = try Self.scan("Gizmo", catalogs: ["A/Little.strings": little, "A/Big.strings": big, "A/Bare.strings": bare])

        #expect(found.files.map(\.path) == ["A/Bare.strings", "A/Big.strings", "A/Little.strings"])
        #expect(found.files[0].lines == [NonCodeMentions.Line(number: 1, kind: .catalogKey)])
        #expect(found.files[1].lines == [NonCodeMentions.Line(number: 2, kind: .catalogKey)])
        #expect(found.files[2].lines == [NonCodeMentions.Line(number: 2, kind: .catalogKey)])
        #expect(found.catalogsRead == 3)
    }

    /// A binary property list is not read and not counted; an XML-plist `.strings` and a `.stringsdict` list their root keys only.
    @Test
    func propertyListsListRootKeysAndBinaryOnesAreNotRead() throws {
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n"
        let xmlStrings = head + "\t<key>Gizmo.Title</key>\n\t<string>Gizmo</string>\n\t<key>Other</key>\n\t<dict>\n\t\t<key>Gizmo</key>\n\t\t<string>x</string>\n\t</dict>\n</dict>\n</plist>\n"
        let stringsdict = head + "\t<key>Shop.Gizmo.count</key>\n\t<dict>\n\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@Gizmo@</string>\n\t\t<key>Gizmo</key>\n\t\t<dict>\n\t\t\t<key>one</key>\n\t\t\t<string>Gizmo</string>\n\t\t</dict>\n\t</dict>\n</dict>\n</plist>\n"
        let binary = Data("bplist00".utf8) + Data("Gizmo".utf8)

        let found = try Self.scan("Gizmo", catalogs: [
            "R/Plain.strings": Data(xmlStrings.utf8), "R/Counts.stringsdict": Data(stringsdict.utf8), "R/Binary.strings": binary,
        ])

        #expect(found.files.map(\.path) == ["R/Counts.stringsdict", "R/Plain.strings"])
        #expect(found.files[0].lines(of: .catalogKey) == [5])
        #expect(found.files[1].lines(of: .catalogKey) == [5])
        #expect(found.catalogsRead == 2)
    }

    /// A minified catalog holding a match key and a lead key on one line lists that line once, as a match.
    @Test
    func aMinifiedLineIsListedOnceAsAMatchIfAnyKeyOnItIsOne() throws {
        let found = try Self.scan("Gizmo", catalogs: ["M/Min.xcstrings": "{\"strings\":{\"Gizmo.Strings.title\":{\"localizations\":{}},\"GizmoTitle\":{}}}"])

        #expect(found.files.first?.lines == [NonCodeMentions.Line(number: 1, kind: .catalogKey)])
    }

    /// A catalog whose lines are all leads prints `lead` alone; the header counts lines, leads included, as file names do.
    @Test
    func leadsAreCountedApartAndPrintedAfterTheMatches() throws {
        let mixed = "{\n\"strings\" : {\n\"Gizmo.a\" : { },\n\"Gizmo.b\" : { },\n\"GizmoTitle\" : { }\n}\n}\n"
        let leadsOnly = "{\n\"strings\" : {\n\"GizmoTitle\" : { }\n}\n}\n"
        let found = try Self.scan("Gizmo", catalogs: ["R/A.xcstrings": mixed, "R/B.xcstrings": leadsOnly])
        let section = WhereNonCodeSection(mentions: found, isAmbiguous: false)

        #expect(section.header == "not code, by written name — 4 catalog-key lines (2 leads):")
        #expect(section.row(found.files[0]) == "  R/A.xcstrings (3): 3, 4 · lead 5")
        #expect(section.row(found.files[1]) == "  R/B.xcstrings (1): lead 3")

        let single = try Self.scan("Gizmo", catalogs: ["R/A.xcstrings": mixed])
        #expect(WhereNonCodeSection(mentions: single, isAmbiguous: false).header == "not code, by written name — 3 catalog-key lines (1 a lead):")
    }

    /// A catalog named for the type is a file name, as a Swift or Markdown file is.
    @Test
    func aCatalogsPathJoinsTheFileNames() throws {
        let found = try Self.scan("Gizmo", catalogs: ["R/Gizmo.strings": "\"a\" = \"b\";\n", "R/GizmoExtras.stringsdict": "<plist></plist>"])

        #expect(found.fileNames == [NonCodeMentions.FileName(path: "R/Gizmo.strings", isLead: false), NonCodeMentions.FileName(path: "R/GizmoExtras.stringsdict", isLead: true)])
        #expect(try Self.scan("gizmo", catalogs: ["R/gizmo.strings": "\"a\" = \"b\";\n"]).fileNames.isEmpty)
    }

    /// Nothing found says how many catalogs were decoded and searched.
    @Test
    func theNoneLineCountsTheCatalogsRead() throws {
        let one = try Self.scan("Gizmo", catalogs: ["R/A.strings": "\"a\" = \"b\";\n"])
        let none = try Self.scan("Gizmo", catalogs: [String: String]())

        #expect(WhereNonCodeSection(mentions: one, isAmbiguous: false).noneLine == "not code, by written name — none in the 0 Swift and 0 Markdown files read, nor in the keys of 1 string catalog; storyboards, xibs, plists and project files not read")
        #expect(WhereNonCodeSection(mentions: none, isAmbiguous: false).noneLine.contains("nor in the keys of 0 string catalogs;"))
    }

    /// The enumerator lists the three catalog suffixes under the Markdown scan's rules, from a git listing and from the walk.
    @Test
    func theEnumeratorListsCatalogsUnderTheMarkdownRules() throws {
        let root = try TemporaryDirectory.make("catalogenum")
        for path in ["R/A.xcstrings", "R/B.strings", "R/C.stringsdict", "R/D.txt", ".build/E.strings", "Vendor/F.strings"] {
            try TestSources.write("x", to: path, in: root)
        }
        var config = SiftConfig()
        config.exclude = ["Vendor/"]
        var listed = FileEnumerator(repoRoot: root, config: config)
        listed.catalogListing = { ["R/B.strings", "R/A.xcstrings", "R/C.stringsdict", "R/D.txt", ".build/E.strings", "Vendor/F.strings"] }

        #expect(listed.catalogFiles() == ["R/A.xcstrings", "R/B.strings", "R/C.stringsdict"])
        #expect(FileEnumerator(repoRoot: root, config: config).catalogFiles() == ["R/A.xcstrings", "R/B.strings", "R/C.stringsdict"])
    }

    /// A built-less repo's `where --refs` shows the catalog row and header, and `--files` counts the catalog among the files with not-code mentions.
    @Test
    func theAnswerListsTheCatalogAndTheFilesViewCountsIt() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("enum Gizmo { case partFits }\n", to: "Sources/Gizmo.swift", in: root)
        try TestSources.write("let g = Gizmo.partFits\n", to: "Sources/Use.swift", in: root)
        try TestSources.write("{\n  \"strings\" : {\n    \"Shop.Gizmo.Strings.partFits\" : { }\n  }\n}\n", to: "Resources/Localizable.xcstrings", in: root)
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)

        let refs = try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))
        let files = try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: WhereOptions(filesOnly: true))

        #expect(refs.contains("1 catalog-key line"), "\(refs)")
        #expect(refs.contains("  Resources/Localizable.xcstrings (1): 3"), "\(refs)")
        #expect(files.contains("  Resources/Localizable.xcstrings (not code 1)"), "\(files)")
    }

    /// A tag written across lines still counts its newlines, so a later key keeps its own line.
    @Test
    func aTagSplitAcrossLinesDoesNotShiftLaterKeys() throws {
        let text = "<?xml version=\"1.0\"?>\n<plist\n  version=\"1.0\">\n<dict\n>\n<key>Gizmo.k</key>\n<string>x</string>\n</dict>\n</plist>\n"
        let found = try Self.scan("Gizmo", catalogs: ["S/Split.stringsdict": text])

        #expect(found.files.first?.lines(of: .catalogKey) == [6])
    }

    /// An old-style dictionary or array value lists nothing inside it, and the key after it keeps its line.
    @Test
    func anOldStyleCollectionValueListsNoInnerKeys() throws {
        let text = "\"a\" = { \"Gizmo\" = \"x\"; \"b\" = ( \"Gizmo\", \"}\" ); /* } */ };\n\"c\" = (\n// )\n\"Gizmo\" );\n\"Gizmo.k\" = \"y\";\n"
        let found = try Self.scan("Gizmo", catalogs: ["S/Nested.strings": text])

        #expect(found.files.first?.lines(of: .catalogKey) == [5])
    }

    /// Newlines inside a `.strings` block comment and inside a quoted value (a backslash-newline too) are counted.
    @Test
    func stringsCommentAndQuoteNewlinesAreCounted() throws {
        let comment = try Self.scan("Gizmo", catalogs: ["S/C.strings": "/* a\nb\nc */\n\"Gizmo.k\" = \"y\";\n"])
        let value = try Self.scan("Gizmo", catalogs: ["S/V.strings": "\"a\" = \"x\\\ny\nz\";\n\"Gizmo.k\" = \"y\";\n"])

        #expect(comment.files.first?.lines(of: .catalogKey) == [4])
        #expect(value.files.first?.lines(of: .catalogKey) == [4])
    }

    /// Newlines inside a DOCTYPE and inside a comment in a `.stringsdict` are counted.
    @Test
    func plistDoctypeAndCommentNewlinesAreCounted() throws {
        let text = "<?xml version=\"1.0\"?>\n<!DOCTYPE plist [\n<!ENTITY a \"b\">\n]>\n<!-- one\ntwo -->\n<plist>\n<dict>\n<key>Gizmo.k</key>\n<string>x</string>\n</dict>\n</plist>\n"
        let found = try Self.scan("Gizmo", catalogs: ["S/Doc.stringsdict": text])

        #expect(found.files.first?.lines(of: .catalogKey) == [9])
    }

    /// A catalog that cannot be decoded is not counted among those read.
    @Test
    func anUndecodableCatalogIsNotCounted() throws {
        let found = try Self.scan("Gizmo", catalogs: ["S/Bad.strings": Data([0xFF, 0x47, 0x69, 0x7A, 0x6D, 0x6F, 0xC3]), "S/Good.strings": Data("\"a\" = \"b\";\n".utf8)])

        #expect(found.catalogsRead == 1)
        #expect(WhereNonCodeSection(mentions: found, isAmbiguous: false).noneLine.contains("nor in the keys of 1 string catalog;"))
    }

    /// A minified catalog with the lead key before the match key lists the line once, as a match.
    @Test
    func aMinifiedLineWithTheLeadFirstIsStillAMatch() throws {
        let found = try Self.scan("Gizmo", catalogs: ["M/Lead.xcstrings": "{\"strings\":{\"GizmoTitle\":{},\"Gizmo.Strings.title\":{}}}"])

        #expect(found.files.first?.lines == [NonCodeMentions.Line(number: 1, kind: .catalogKey)])
    }

    /// A root-level key outside `strings` is not listed.
    @Test
    func aRootKeyOutsideStringsIsNotListed() throws {
        let found = try Self.scan("Gizmo", catalogs: ["M/Root.xcstrings": "{\"Gizmo\" : 1,\n\"strings\" : {\n\"Other\" : { }\n}}"])

        #expect(found.files.isEmpty)
        #expect(found.catalogsRead == 1)
    }

    /// An escaped surrogate pair in a catalog key reads as the one character it spells, as the raw character does.
    @Test
    func anEscapedSurrogatePairReadsAsOneCharacter() throws {
        let escape = "\\u"
        let text = "{\n\"strings\" : {\n\"Gizmo\u{1F600}\" : { },\n\"Gizmo\(escape)D83D\(escape)DE00\" : { },\n\"Gizmo\(escape)d83d\(escape)DE00\" : { }\n}\n}\n"
        let found = try Self.scan("Gizmo", catalogs: ["Resources/Pair.xcstrings": text])

        let expected = [3, 4, 5].map { NonCodeMentions.Line(number: $0, kind: .catalogKey, isLead: true) }

        #expect(found.files.first?.lines == expected)
    }

    /// A lone surrogate escape reads as the replacement character and leaves none of its digits in the key.
    @Test
    func aLoneSurrogateEscapeLeavesNoHexText() throws {
        let escape = "\\u"
        let text = "{\n\"strings\" : {\n\"Gizmo\(escape)D83D\" : { },\n\"Gizmo\(escape)DE00X\" : { },\n\"Gizmo\(escape)D83D\(escape)0041\" : { }\n}\n}\n"
        let found = try Self.scan("Gizmo", catalogs: ["Resources/Lone.xcstrings": text])

        let expected = [3, 4, 5].map { NonCodeMentions.Line(number: $0, kind: .catalogKey, isLead: true) }

        #expect(found.files.first?.lines == expected)
    }

    /// Numeric character references in a property list key read as the characters they spell, and a decoded ampersand is not decoded again.
    @Test
    func numericCharacterReferencesAreDecodedOnce() throws {
        let keys = ["Gizmo.k", "Gizmo&#46;k", "Gizmo&#x2E;k", "Gizmo&amp;#46;k", "Gizmo&#xZZ;k", "Gizmo&#1114112;k"]
        let body = keys.map { "<key>\($0)</key>\n<string>x</string>" }.joined(separator: "\n")
        let text = "<?xml version=\"1.0\"?>\n<plist>\n<dict>\n\(body)\n</dict>\n</plist>\n"
        let found = try Self.scan("Gizmo", catalogs: ["S/Refs.stringsdict": text])

        #expect(found.files.first?.lines == [
            NonCodeMentions.Line(number: 4, kind: .catalogKey),
            NonCodeMentions.Line(number: 6, kind: .catalogKey),
            NonCodeMentions.Line(number: 8, kind: .catalogKey),
            NonCodeMentions.Line(number: 10, kind: .catalogKey, isLead: true),
            NonCodeMentions.Line(number: 12, kind: .catalogKey, isLead: true),
            NonCodeMentions.Line(number: 14, kind: .catalogKey, isLead: true),
        ])
    }

    /// A numeric character reference of any length, zero-padded or not, reads as the character it spells.
    @Test
    func zeroPaddedNumericReferencesAreDecoded() throws {
        let keys = ["Gizmo.k", "Gizmo&#0000000046;k", "Gizmo&#x0000" + "2E;k"]
        let body = keys.map { "<key>\($0)</key>\n<string>x</string>" }.joined(separator: "\n")
        let text = "<?xml version=\"1.0\"?>\n<plist>\n<dict>\n\(body)\n</dict>\n</plist>\n"
        let found = try Self.scan("Gizmo", catalogs: ["S/Padded.stringsdict": text])

        #expect(found.files.first?.lines == [4, 6, 8].map { NonCodeMentions.Line(number: $0, kind: .catalogKey) })
    }

    /// A key written in decomposed form matches the composed name, as the characters compare equal, even in a file that also holds the composed spelling.
    @Test
    func aDecomposedKeyMatchesTheComposedName() throws {
        let text = "{\n\"strings\" : {\n\"Gizm\u{E9}.k\" : { },\n\"Gizme\u{301}.k\" : { }\n}\n}\n"
        let found = try Self.scan("Gizm\u{E9}", catalogs: ["Resources/Composed.xcstrings": text])

        #expect(found.files.first?.lines == [3, 4].map { NonCodeMentions.Line(number: $0, kind: .catalogKey) })
    }

    /// A non-ASCII name is found in a catalog that writes it only as an escape.
    @Test
    func aNonASCIINameIsFoundWhereACatalogEscapesIt() throws {
        let json = "{\n\"strings\" : {\n\"Gizm\\u\("00E9").k\" : { }\n}\n}\n"
        let plist = "<?xml version=\"1.0\"?>\n<plist>\n<dict>\n<key>Gizm&#233;.k</key>\n<string>x</string>\n</dict>\n</plist>\n"
        let found = try Self.scan("Gizm\u{E9}", catalogs: ["Resources/Escaped.xcstrings": json, "S/Escaped.stringsdict": plist])

        #expect(found.files.first { $0.path.hasSuffix(".xcstrings") }?.lines == [NonCodeMentions.Line(number: 3, kind: .catalogKey)])
        #expect(found.files.first { $0.path.hasSuffix(".stringsdict") }?.lines == [NonCodeMentions.Line(number: 4, kind: .catalogKey)])
    }
}
