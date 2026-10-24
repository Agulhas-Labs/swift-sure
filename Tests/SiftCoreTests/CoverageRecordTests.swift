//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The coverage a `run --coverage` measured is kept as one file in the repository, replaced by each run that measures, never appended to.
@Suite(.temporaryDirectories)
struct CoverageRecordTests {
    private static func record(tree: String) -> CoverageRecord {
        CoverageRecord(tree: tree, command: ["swift", "test", "--enable-code-coverage"], measured: ["Sources/Kit/Shape.swift": [2: 3, 3: 3, 4: 0, 5: 3]], unmeasured: [])
    }

    @Test func aLaterRunReplacesTheRecord() throws {
        let root = try TestSources.makeTempRepo()
        try Self.record(tree: "aaaaaaaaaaaaaaaa").write(in: root)
        let later = Self.record(tree: "bbbbbbbbbbbbbbbb")
        try later.write(in: root)

        let written = try JSONDecoder().decode(CoverageRecord.self, from: Data(contentsOf: CoverageRecord.location(in: root)))

        #expect(written == later)
        #expect(try FileManager.default.contentsOfDirectory(atPath: SiftPaths.cache(in: root).path).filter { $0.hasPrefix("coverage") } == ["coverage.json"])
    }
}
