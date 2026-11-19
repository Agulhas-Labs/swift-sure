//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A too-common name's owner-qualified narrowing keeps exactly the sites it keeps reading every file that writes the name, while reading only the files the scan saw spell `Owner.name` or `>.name`.
@Suite(.temporaryDirectories)
struct OwnerQualifiedNarrowingEquivalenceTests {
    private static let owners: Set<String> = ["Gizmo"]

    /// The files of the fixture: `line` is written in more files than a name may be and still count, and qualified by `Gizmo` in each way the narrowing reads.
    private static var files: [String: String] {
        var files = [
            "Sources/Lib/Gizmo.swift": "public enum Gizmo {\n    public static func line(count: Int) -> String {\n        String(count)\n    }\n}\n",
            "Sources/Lib/Plain.swift": "func plain() -> String {\n    Gizmo.line(count: 1)\n}\n",
            "Sources/Lib/Module.swift": "func module() -> String {\n    Lib.Gizmo.line(count: 2)\n}\n",
            "Sources/Lib/Generic.swift": "func generic() -> String {\n    Gizmo<Int>.line(count: 3)\n}\n",
            "Sources/Lib/Bare.swift": "extension Gizmo {\n    static func bare() -> String {\n        line(count: 4)\n    }\n}\n",
            "Sources/Lib/Depot.swift": "extension Gizmo {\n    static func depot() -> String {\n        Self.line(count: 5)\n    }\n}\n",
            "Sources/Lib/Split.swift": "func split() -> String {\n    Gizmo\n        .line(count: 6)\n}\n",
            "Sources/Lib/Text.swift": "// Gizmo.line(count: 7)\nlet text = \"Gizmo.line\"\nfunc text() -> Int {\n    Pump0().line(count: 7)\n}\n",
        ]
        for index in 0 ... AffectedRenderer.nameEvidenceFileCap {
            files["Sources/Lib/Crowd\(index).swift"] = "public struct Pump\(index) {\n    public func line(count: Int) -> Int {\n        count\n    }\n}\n\npublic func crowd\(index)() -> Int {\n    Pump\(index)().line(count: \(index))\n}\n"
        }
        return files
    }

    /// The files read to spell `Owner.name` or `>.name`: the qualified ones, and the one writing `Gizmo.line` in a comment and a string, which a text check cannot tell from code.
    private static let read: Set<String> = ["Sources/Lib/Plain.swift", "Sources/Lib/Module.swift", "Sources/Lib/Generic.swift", "Sources/Lib/Text.swift"]

    private static func fixture() throws -> URL {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        return root
    }

    /// The narrowed sites, and the paths read to find them.
    private static func narrowing(_ sites: [NameMention], spellings: MemberSpellings, root: URL) -> (kept: [NameMention], read: Set<String>) {
        var read: Set<String> = []
        let kept = OwnerQualifiedMentions.narrowing(sites, name: "line", owners: owners, spellings: spellings, rootPath: root.path) { path in
            read.insert(String(path.dropFirst(root.path.count + 1)))
            return FileManager.default.contents(atPath: path)
        }
        return (kept, read)
    }

    @Test
    func theWrittenNameScanKeepsTheSameSitesAndReadsOnlyTheQualifyingFiles() async throws {
        let root = try Self.fixture()
        let found = await NameMentionScanner(repoRoot: root, enumerator: FileEnumerator(repoRoot: root, config: SiftConfig())).mentions(of: ["line"])
        let sites = try #require(found.sites["line"])
        #expect(Set(sites.map(\.path)).count > AffectedRenderer.nameEvidenceFileCap)
        let everyFile = Self.narrowing(sites, spellings: MemberSpellings(), root: root)
        let spelled = Self.narrowing(sites, spellings: found.spellings, root: root)
        #expect(spelled.kept == everyFile.kept)
        #expect(spelled.kept == [
            NameMention(path: "Sources/Lib/Generic.swift", line: 2),
            NameMention(path: "Sources/Lib/Module.swift", line: 2),
            NameMention(path: "Sources/Lib/Plain.swift", line: 2),
        ])
        #expect(everyFile.read == Set(sites.map(\.path)))
        #expect(spelled.read == Self.read)
    }

    @Test
    func theCallSiteScanKeepsTheSameSitesAndReadsOnlyTheQualifyingFiles() async throws {
        let root = try Self.fixture()
        let found = await CallSiteScanner(repoRoot: root, enumerator: FileEnumerator(repoRoot: root, config: SiftConfig())).callSites(named: ["line": .call], spelling: true)
        let sites = try #require(found.sites["line"]).map { NameMention(path: $0.path, line: $0.line) }
        let everyFile = Self.narrowing(sites, spellings: MemberSpellings(), root: root)
        let spelled = Self.narrowing(sites, spellings: found.spellings, root: root)

        #expect(spelled.kept == everyFile.kept)
        #expect(Set(spelled.kept.map(\.path)) == ["Sources/Lib/Generic.swift", "Sources/Lib/Module.swift", "Sources/Lib/Plain.swift"])
        #expect(everyFile.read == Set(sites.map(\.path)))
        #expect(spelled.read == Self.read)
    }

    /// A file the scan recorded nothing for, as for a name it was not asked about, is read.
    @Test
    func aFileWithNoRecordIsRead() async throws {
        let root = try Self.fixture()
        let scanner = NameMentionScanner(repoRoot: root, enumerator: FileEnumerator(repoRoot: root, config: SiftConfig()))
        let sites = try #require(await scanner.mentions(of: ["line"]).sites["line"])
        let otherName = await scanner.mentions(of: ["Pump0"]).spellings

        #expect(Self.narrowing(sites, spellings: otherName, root: root).read == Set(sites.map(\.path)))
    }
}
