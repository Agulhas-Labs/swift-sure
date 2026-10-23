//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the path the `in … (syntactic)` line states: the form the failure's own heading uses, so it opens from wherever the run was started.
@Suite(.temporaryDirectories)
struct RunSiteLineSubdirectoryTests {
    @Test
    func theSiteLinesPathResolvesFromTheDirectoryTheRunStartedIn() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.source, to: Self.path, in: root)
        try TestSources.commitAll(in: root, message: "sources")
        try await SiftEngine(directory: root).ensureFresh()
        let location = "DepotStoreTests.swift:11:9"
        let sites = RunFailureSites.resolving([location], inRepositoryAt: root)

        let inside = Self.answer(at: location, sites: sites, in: root.appendingPathComponent("Tests"))
        #expect(inside.contains("    in DepotStoreTests.restock() — LibTests/DepotStoreTests.swift:10-12 (syntactic)"))

        let beside = Self.answer(at: location, sites: sites, in: root.appendingPathComponent("Sources"))
        #expect(beside.contains("    in DepotStoreTests.restock() — \(root.path)/\(Self.path):10-12 (syntactic)"))
    }
}

private extension RunSiteLineSubdirectoryTests {
    static var path: String {
        "Tests/LibTests/DepotStoreTests.swift"
    }

    /// A helper on lines 10-12 holding the failing expectation on line 11.
    static var source: String {
        """
        //
        // Copyright © Agulhas Labs
        //

        import Testing

        struct DepotStoreTests {
            @Test
            func aFailingTest() {}
            func restock() {
                #expect(Bool(false))
            }
        }

        """
    }

    static func answer(at location: String, sites: RunFailureSites, in directory: URL) -> [String] {
        var filter = RunOutputFilter(invokedAs: ["swift", "test"])
        for line in [
            "✘ Test aFailingTest() recorded an issue at \(location): Expectation failed: Bool(false)",
            "✘ Test run with 1 test in 1 suite failed after 0.010 seconds with 1 issue.",
        ] {
            filter.consume(line: line)
        }
        return RunReportRenderer(kind: .swiftTest, workingDirectory: directory, changedFiles: .of([]), sites: sites)
            .render(filter.finish(exitCode: 1), exitCode: 1, logURL: nil)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
