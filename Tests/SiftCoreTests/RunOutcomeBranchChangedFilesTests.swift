//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Pins that the answer a run serves measures its failures against the branch's commits as well as the dirty tree.
@Suite(.temporaryDirectories)
struct RunOutcomeBranchChangedFilesTests {
    @Test
    func aFailureInAFileTheBranchCommittedOnACleanTreeReadsInAChangedFileSinceMain() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("enum A {}\n", to: "Sources/App/Catalogue.swift", in: root)
        try TestSources.commitAll(in: root, message: "add")
        try TestSources.runGit(["checkout", "-b", "feature/work"], in: root)
        try TestSources.write("enum A { static let b = 1 }\n", to: "Sources/App/Catalogue.swift", in: root)
        try TestSources.commitAll(in: root, message: "change")
        let report = RunReport(
            errors: [],
            warnings: [],
            testFailures: [RunTestFailure(name: "testA()", location: "Catalogue.swift:3:9", message: "Expectation failed")],
            summaryLines: [],
            contract: .runTally,
            verdict: nil,
            tally: nil,
            totalLines: 10
        )
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: 1, report: report, log: nil, repositoryRoot: root)

        let answer = try #require(outcome.filteredAnswer(workingDirectory: root))

        #expect(answer.text.contains("in a changed file since main"))
    }
}
