//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers when a linked worktree is given its own derived data: only once the cache directory is excluded in the shared git directory, and never on a `rev-parse` that does not answer in time.
@Suite(.temporaryDirectories)
struct WorktreeDerivedDataExcludeTests {
    private func linkedWorktree(sourceLocation: SourceLocation = #_sourceLocation) throws -> (worktree: URL, common: URL) {
        let repo = try TestSources.makeTempRepo()
        let worktree = try TestSources.makeWorktree(of: repo, named: "wt")
        return try (worktree, #require(GitContext.commonDirectory(of: worktree), sourceLocation: sourceLocation))
    }

    @Test
    func aCommonDirectoryThatCannotBeWrittenChoosesNothing() throws {
        let (worktree, common) = try linkedWorktree()
        let info = common.appendingPathComponent("info", isDirectory: true)
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let locked: [URL] = [info, common]
        for url in locked {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
        }
        defer {
            for url in locked {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        try #require(!FileManager.default.isWritableFile(atPath: info.path), "the fixture directory is still writable")

        #expect(WorktreeDerivedData.chosen(repositoryRoot: worktree, passThrough: []) == nil)
    }

    @Test
    func aNegatedEntryDoesNotStandInForTheExclude() throws {
        let (worktree, common) = try linkedWorktree()
        let exclude = common.appendingPathComponent("info/exclude")
        try FileManager.default.createDirectory(at: exclude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("!.swift-sure/\n".utf8).write(to: exclude)

        let chosen = WorktreeDerivedData.chosen(repositoryRoot: worktree, passThrough: [])

        #expect(chosen != nil)
        let lines = try String(contentsOf: exclude, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines == ["!.swift-sure/", ".swift-sure/"])
    }

    @Test
    func anEntryAlreadyThereIsLeftAloneAndStillChooses() throws {
        let (worktree, common) = try linkedWorktree()
        let exclude = common.appendingPathComponent("info/exclude")
        try FileManager.default.createDirectory(at: exclude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# mine\n.swift-sure/\n".utf8).write(to: exclude)

        #expect(WorktreeDerivedData.chosen(repositoryRoot: worktree, passThrough: []) != nil)
        #expect(try String(contentsOf: exclude, encoding: .utf8) == "# mine\n.swift-sure/\n")
    }

    @Test
    func aRevParseThatDoesNotAnswerInTimeChoosesNothing() throws {
        let root = try TemporaryDirectory.make("derived-data-silent-git")
        let dotGit = root.appendingPathComponent(".git", isDirectory: true)
        for sub in ["objects", "refs"] {
            try FileManager.default.createDirectory(at: dotGit.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try Data("ref: refs/heads/main\n".utf8).write(to: dotGit.appendingPathComponent("HEAD"))
        let fifo = root.appendingPathComponent("config.fifo").path
        guard mkfifo(fifo, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try Data("[core]\n\trepositoryformatversion = 0\n[include]\n\tpath = \(fifo)\n".utf8).write(to: dotGit.appendingPathComponent("config"))
        defer {
            let descriptor = open(fifo, O_WRONLY | O_NONBLOCK)
            if descriptor >= 0 {
                close(descriptor)
            }
        }

        let chosen = WorktreeDerivedData.chosen(repositoryRoot: root, passThrough: [], within: 0.3)

        #expect(chosen == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".swift-sure").path))
    }
}
