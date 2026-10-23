//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
import Testing

/// The two `swift-sure test` paths besides the simulator request, `--sweep` and the SwiftPM package run, put the question of which repository a directory is in to a git that never answers, and are refused in the unanswered wording within a deadline, never as no repository, never hung.
///
/// The fixture is a repository whose config includes a FIFO nobody writes, so `git rev-parse` blocks there until its bound ends it.
@Suite(.temporaryDirectories)
struct TestCommandUnansweredRootTests {
    /// How long a refusal is waited for: well past the two-second bound a git read has, so only a call with no bound at all misses it.
    private static let budget = 20

    /// `--sweep` in such a tree is refused as unanswered, and does not go on to sweep or to report a repository it does not know.
    @Test
    func aSweepInATreeGitDoesNotAnswerForIsRefusedAsUnanswered() async throws {
        let root = try TemporaryDirectory.make("test-sweep-unanswered")
        let fifo = try Self.blockGitReads(in: root)
        defer { Self.release(fifo) }

        let outcome = await Deadline.within(seconds: Self.budget) { () -> String? in
            do {
                var command = try TestCommand.parse(["--sweep"])
                command.startingDirectory = root
                try await command.run()
                return nil
            } catch {
                return TestCommand.message(for: error)
            }
        }
        Self.release(fifo)

        let refusal = try #require(outcome, "--sweep was still waiting on git after \(Self.budget) seconds: the root question has no bound")
        let text = try #require(refusal, "--sweep went ahead over a tree git did not answer for")

        #expect(text.contains("git did not answer within"), "\(text)")
        #expect(!text.contains("swift-sure test --sweep runs inside a git repository"), "\(text)")
    }

    /// The package run in such a tree is refused as unanswered, and does not go on to run `swift test` or to report no repository.
    @Test
    func aPackageRunInATreeGitDoesNotAnswerForIsRefusedAsUnanswered() async throws {
        let root = try TemporaryDirectory.make("test-package-unanswered")
        try Data("// swift-tools-version: 6.0\n".utf8).write(to: root.appendingPathComponent("Package.swift"))
        let fifo = try Self.blockGitReads(in: root)
        defer { Self.release(fifo) }

        let outcome = await Deadline.within(seconds: Self.budget) { () -> String? in
            do {
                let command = try TestCommand.parse([])
                _ = try command.packageRun(in: root)
                return nil
            } catch {
                return TestCommand.message(for: error)
            }
        }
        Self.release(fifo)

        let refusal = try #require(outcome, "the package run was still waiting on git after \(Self.budget) seconds: the root question has no bound")
        let text = try #require(refusal, "the package run went ahead over a tree git did not answer for")

        #expect(text.contains("git did not answer within"), "\(text)")
        #expect(!text.contains("swift-sure test runs inside a git repository"), "\(text)")
    }
}

private extension TestCommandUnansweredRootTests {
    /// Makes `root` a repository whose config includes a FIFO nobody writes, so `git rev-parse` blocks there until its bound ends it; answers the FIFO's path.
    static func blockGitReads(in root: URL) throws -> String {
        let git = root.appendingPathComponent(".git", isDirectory: true)
        for sub in ["objects", "refs"] {
            try FileManager.default.createDirectory(at: git.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try Data("ref: refs/heads/main\n".utf8).write(to: git.appendingPathComponent("HEAD"))
        let fifo = root.appendingPathComponent("config.fifo").path
        guard mkfifo(fifo, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try Data("[core]\n\trepositoryformatversion = 0\n[include]\n\tpath = \(fifo)\n".utf8).write(to: git.appendingPathComponent("config"))
        return fifo
    }

    /// Opens the FIFO's write end without blocking, which releases any git still blocked reading it, then closes it.
    static func release(_ fifo: String) {
        let descriptor = open(fifo, O_WRONLY | O_NONBLOCK)
        if descriptor >= 0 {
            close(descriptor)
        }
    }
}
