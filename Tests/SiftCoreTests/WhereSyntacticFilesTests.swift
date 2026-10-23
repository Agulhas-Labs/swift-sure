//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The files view of a no-store `--refs` sweep (`where --syntactic --refs --files`): one row per file with its counts and no site, paged on the offset cursor as the store's view is.
@Suite(.temporaryDirectories)
struct WhereSyntacticFilesTests {
    private static var fileCount: Int {
        WhereFilesCollector.filesListCap + 5
    }

    /// `Gizmo` declared once and used, by written name, in more files than one page of the view lists; every user names it on two lines.
    private static func engine() async throws -> SiftEngine {
        var files = ["Sources/Alpha/Gizmo.swift": "struct Gizmo {}\n"]
        for index in 0 ..< fileCount {
            let name = String(format: "Use%03d", index)
            files["Sources/Alpha/\(name).swift"] = "func \(name)() {\n    let a = Gizmo()\n    let b = Gizmo()\n}\n"
        }
        return try await TestSources.engine(files: files)
    }

    private static func render(files: Bool, offset: Int = 0) async throws -> String {
        let engine = try await engine()
        let options = WhereOptions(includeSemantic: false, includeReferences: true, offset: offset, filesOnly: files)
        return try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: options)
    }

    @Test
    func filesListsEachFileWithItsCountAndNoSite() async throws {
        let output = try await Self.render(files: true)

        #expect(output.contains("files naming Sources.Gizmo (\(Self.fileCount + 1) files: \(Self.fileCount) with code sites"))
        #expect(output.contains("  Sources/Alpha/Use000.swift (2)"))
        #expect(output.contains("  Sources/Alpha/Gizmo.swift (declares)"))
        #expect(!output.contains("Use000.swift (2): "))
        #expect(!output.contains("grep for the name"))
    }

    @Test
    func filesPagesOnTheOffsetCursor() async throws {
        let first = try await Self.render(files: true)
        let cap = WhereFilesCollector.filesListCap

        #expect(first.contains("truncated: \(Self.fileCount + 1 - cap) more files — pass offset \(cap) to continue"))
        #expect(!first.contains("Use\(String(format: "%03d", Self.fileCount - 1)).swift"))

        let second = try await Self.render(files: true, offset: cap)
        #expect(second.contains("(…\(cap) files skipped)"))
        #expect(second.contains("Use\(String(format: "%03d", Self.fileCount - 1)).swift (2)"))
        #expect(!second.contains("truncated:"))
    }

    @Test
    func refsWithoutFilesStillListsSites() async throws {
        let output = try await Self.render(files: false)

        #expect(output.contains("Sources/Alpha/Use000.swift (2)"))
        #expect(!output.contains("files naming"))
    }
}
