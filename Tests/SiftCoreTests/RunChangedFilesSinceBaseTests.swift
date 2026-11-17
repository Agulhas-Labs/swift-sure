//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers what "changed" means on a feature branch: the dirty tree and what the branch's own commits changed since the default branch, so a clean worktree of work already committed does not read as having changed nothing.
@Suite(.temporaryDirectories)
struct RunChangedFilesSinceBaseTests {
    @Test
    func aFileTheBranchCommittedIsChangedOnACleanTreeAndNamesMainAsItsBase() throws {
        let root = try Self.branchRepo()

        #expect(RunChangedFiles.onBranch(at: root) == .sinceBase(["Catalogue.swift"], base: "main"))
    }

    @Test
    func aFailureInACommittedFileReadsInAChangedFileSinceMainAndOneInAnUntouchedFileDoesNot() throws {
        let root = try Self.branchRepo()
        let changed = RunChangedFiles.onBranch(at: root)

        #expect(Self.census(file: "Catalogue.swift", changed).loneSuffix() == " (in a changed file since main)")
        #expect(Self.census(file: "Untouched.swift", changed).loneSuffix() == " (not in a changed file since main)")
        #expect(Self.census(file: "Untouched.swift", changed).loneSuffix(dashed: true) == " — not in a changed file since main")
        #expect(Self.census(file: "Untouched.swift", changed).measurements(of: "failure").hasSuffix("0 in changed files since main (matched by name)"))
    }

    @Test
    func onTheDefaultBranchTheAnswerIsTheDirtyTreeAloneWithTodaysWording() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("enum A {}\n", to: "Sources/App/Catalogue.swift", in: root)
        try TestSources.commitAll(in: root, message: "add")
        try TestSources.write("enum A { static let b = 1 }\n", to: "Sources/App/Catalogue.swift", in: root)

        let changed = RunChangedFiles.onBranch(at: root)

        #expect(changed == .basenames(["Catalogue.swift"]))
        #expect(Self.census(file: "Untouched.swift", changed).loneSuffix() == " (not in a changed file)")
    }

    @Test
    func aBranchWithNoCommitsOfItsOwnHasNoBase() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.runGit(["checkout", "-b", "feature/empty"], in: root)

        #expect(RunChangedFiles.onBranch(at: root) == .basenames([]))
    }

    @Test
    func theDirtyTreeAndTheBranchCommitsAreUnioned() throws {
        let root = try Self.branchRepo()
        try TestSources.write("enum New {}\n", to: "Sources/App/New.swift", in: root)

        #expect(RunChangedFiles.onBranch(at: root) == .sinceBase(["Catalogue.swift", "New.swift"], base: "main"))
    }

    @Test
    func aRenameOnTheBranchListsTheNewNameOnly() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("enum Original { static let value = 1 }\n", to: "Sources/App/Before.swift", in: root)
        try TestSources.commitAll(in: root, message: "add")
        try TestSources.runGit(["checkout", "-b", "feature/rename"], in: root)
        try TestSources.runGit(["mv", "Sources/App/Before.swift", "Sources/App/After.swift"], in: root)
        try TestSources.runGit(["commit", "-m", "rename"], in: root)

        #expect(RunChangedFiles.onBranch(at: root) == .sinceBase(["After.swift"], base: "main"))
    }

    /// A repository whose `main` holds two files and whose `feature/work` committed a change to one of them, leaving the tree clean.
    private static func branchRepo() throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("enum A {}\n", to: "Sources/App/Catalogue.swift", in: root)
        try TestSources.write("enum B {}\n", to: "Sources/App/Untouched.swift", in: root)
        try TestSources.commitAll(in: root, message: "add")
        try TestSources.runGit(["checkout", "-b", "feature/work"], in: root)
        try TestSources.write("enum A { static let b = 1 }\n", to: "Sources/App/Catalogue.swift", in: root)
        try TestSources.commitAll(in: root, message: "change")
        return root
    }

    private static func census(file: String, _ changed: RunChangedFiles) -> RunFailureCensus {
        RunFailureCensus.of([file], message: { _ in "Expectation failed" }, path: { $0 }, changedFiles: changed)
    }
}
