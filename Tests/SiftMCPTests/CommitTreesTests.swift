//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
@testable import SiftMCP
import Testing

/// The live tree-to-commit lookup behind `swift-sure report --deploys`, run against a real repository: the stubbed lookups elsewhere cannot catch a changed format or a lost root.
@Suite(.temporaryDirectories)
struct CommitTreesTests {
    /// Each commit comes back as its short hash with its full tree hash, newest first, and `limit` bounds how many.
    @Test
    func commitTreesPairsEachCommitWithItsTreeNewestFirst() throws {
        let repository = try Self.repository(commits: 3)

        let all = try #require(GitContext(repoRoot: repository).commitTrees(limit: 10))
        let commits = try (0 ..< 3).map { try Self.git(["rev-parse", "--short", "HEAD~\($0)"], in: repository) }
        let trees = try (0 ..< 3).map { try Self.git(["rev-parse", "HEAD~\($0)^{tree}"], in: repository) }

        #expect(all.map(\.commit) == commits)
        #expect(all.map(\.tree) == trees)
        #expect(all.allSatisfy { $0.tree.count >= 40 })
        #expect(try #require(GitContext(repoRoot: repository).commitTrees(limit: 2)).count == 2)
    }

    /// Inside a repository the default lookup finds the commit that has a tree; outside one it finds nothing.
    @Test
    func theDirectoryLookupFindsCommitsInARepositoryAndNothingOutsideOne() throws {
        let repository = try Self.repository(commits: 3)
        let tree = try Self.git(["rev-parse", "HEAD~1^{tree}"], in: repository)
        let commit = try Self.git(["rev-parse", "--short", "HEAD~1"], in: repository)

        let found = DeployLog.treeCommits(enclosing: repository)
        let outside = try TemporaryDirectory.make("commit-trees-outside")

        #expect(found.first { $0.tree == tree }?.commit == commit)
        #expect(DeployLog.treeCommits(enclosing: outside).isEmpty)
    }

    /// A commit made in a linked worktree, and one on a branch nobody has checked out, are listed from the primary checkout.
    @Test
    func commitsOnOtherWorktreesAndOtherBranchesAreListed() throws {
        let repository = try Self.repository(commits: 1)
        let linked = repository.appendingPathComponent("linked")
        _ = try Self.git(["worktree", "add", "-q", "--detach", linked.path], in: repository)
        defer { _ = try? Self.git(["worktree", "remove", "--force", linked.path], in: repository) }
        try #require(FileManager.default.fileExists(atPath: linked.appendingPathComponent(".git").path), "the linked worktree was not made inside the fixture")
        try "linked".write(to: linked.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        _ = try Self.git(["add", "file.txt"], in: linked)
        _ = try Self.git(Self.commitArguments("linked"), in: linked)
        let linkedCommit = try Self.git(["rev-parse", "--short", "HEAD"], in: linked)
        let linkedTree = try Self.git(["rev-parse", "HEAD^{tree}"], in: linked)

        _ = try Self.git(["branch", "side"], in: repository)
        _ = try Self.git(["checkout", "-q", "side"], in: repository)
        try "side".write(to: repository.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        _ = try Self.git(["add", "file.txt"], in: repository)
        _ = try Self.git(Self.commitArguments("side"), in: repository)
        let sideCommit = try Self.git(["rev-parse", "--short", "HEAD"], in: repository)
        let sideTree = try Self.git(["rev-parse", "HEAD^{tree}"], in: repository)
        _ = try Self.git(["checkout", "-q", "-"], in: repository)

        let found = try #require(GitContext(repoRoot: repository).commitTrees(limit: 10))

        #expect(found.first { $0.tree == linkedTree }?.commit == linkedCommit)
        #expect(found.first { $0.tree == sideTree }?.commit == sideCommit)
    }

    /// A stash and a rewrite's backup hold commits with HEAD's tree that no branch reaches, so neither is listed: a deploy of that tree would be named by a commit on no branch.
    @Test
    func stashAndRewriteBackupCommitsAreNotListed() throws {
        let repository = try Self.repository(commits: 1)
        let head = try Self.git(["rev-parse", "--short", "HEAD"], in: repository)
        try "loose".write(to: repository.appendingPathComponent("loose.txt"), atomically: true, encoding: .utf8)
        _ = try Self.git(["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", "stash", "-q", "-u"], in: repository)
        let backup = try Self.git(["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", "commit-tree", "HEAD^{tree}", "-m", "backup"], in: repository)
        _ = try Self.git(["update-ref", "refs/original/refs/heads/main", backup], in: repository)
        try #require(try Self.git(["rev-list", "--count", "--all"], in: repository) != "1", "the stash and the backup made no commits")

        let found = try #require(GitContext(repoRoot: repository).commitTrees(limit: 10))

        #expect(found.map(\.commit) == [head])
    }

    /// An empty value in the log names no tree, so no commit is appended to it.
    @Test
    func anEmptyTreeValueGetsNoCommitAppended() throws {
        let directory = try TemporaryDirectory.make("commit-trees-empty")
        let log = directory.appendingPathComponent("deploys.jsonl")
        let tail = #""version":"0.1.8","tree":"clean","binarySize":1000000}"#
        let lines = [
            #"{"ts":"2026-10-11T08:00:00Z","commit":null,"sourceTree":"","# + tail,
            #"{"ts":"2026-10-12T08:00:00Z","commit":"","# + tail,
        ]
        try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)

        let page = DeployLog.render(fileURL: log, trees: { [(commit: "abc1234", tree: "def")] })

        #expect(page.components(separatedBy: "\n") == [
            "2026-10-11T08:00:00Z  tree   0.1.8  clean  1.0 MB",
            "2026-10-12T08:00:00Z    0.1.8  clean  1.0 MB",
        ])
    }

    /// A repository with `commits` commits, each changing the tree, made with git's own variables removed.
    private static func repository(commits: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        let directory = try TemporaryDirectory.make("commit-trees-repo", sourceLocation: sourceLocation)
        _ = try git(["init", "-q"], in: directory)
        try #require(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path), "the fixture's repository was not made inside its own directory", sourceLocation: sourceLocation)
        for number in 1 ... commits {
            try "\(number)".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            _ = try git(["add", "file.txt"], in: directory)
            _ = try git(["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "c\(number)"], in: directory)
        }
        return directory
    }

    private static func commitArguments(_ message: String) -> [String] {
        ["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", "commit", "-q", "-m", message]
    }

    private static func git(_ arguments: [String], in directory: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, sourceLocation: sourceLocation)
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
