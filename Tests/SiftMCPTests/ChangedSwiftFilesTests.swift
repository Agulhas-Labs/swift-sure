//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// The Swift files a repository lists as changed inside a span: tracked and untracked ones, never an ignored one, and none changed outside it.
@Suite(.temporaryDirectories)
struct ChangedSwiftFilesTests {
    private func write(_ repo: URL, _ relative: String, _ text: String = "struct Probe {}\n") throws {
        let url = repo.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func listsTrackedAndUntrackedFilesChangedInTheSpanAndNeitherIgnoredNorOutsideOnes() throws {
        let repo = try MCPTestRepo.make(declaring: "Depot")
        try write(repo, ".gitignore", "Ignored/\n")
        try write(repo, "Sources/App/Early.swift")
        Thread.sleep(forTimeInterval: 0.05)
        let start = Date().timeIntervalSince1970
        try write(repo, "Sources/App/Depot.swift")
        try write(repo, "Sources/App/Fresh.swift")
        try write(repo, "Ignored/Skip.swift")
        let end = Date().timeIntervalSince1970
        Thread.sleep(forTimeInterval: 0.05)

        let listed = ChangedSwiftFiles.under(repo.path, changedWithin: [start ... end]).map { URL(fileURLWithPath: $0).lastPathComponent }

        #expect(listed == ["Depot.swift", "Fresh.swift"])
    }

    @Test
    func reportsTheEndOfTheLatestSpanHoldingEachChange() throws {
        let repo = try MCPTestRepo.make(declaring: "Depot")
        Thread.sleep(forTimeInterval: 0.05)
        let start = Date().timeIntervalSince1970
        try write(repo, "Sources/App/Depot.swift")
        let end = Date().timeIntervalSince1970

        let found = ChangedSwiftFiles.withSpanEnds(under: repo.path, changedWithin: [start ... end, (end + 10) ... (end + 20)])

        #expect(found.map(\.spanEnd) == [end])
    }
}
