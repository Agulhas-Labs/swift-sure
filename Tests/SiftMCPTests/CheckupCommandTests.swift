//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure checkup` as the command line runs it: the range is `diff`'s and refused in `checkup`'s name, every check is named once, and the standing statement is in the help and not in an answer.
@Suite(.temporaryDirectories)
struct CheckupCommandTests {
    private static var statement: String {
        "builds nothing and runs nothing"
    }

    private static func temporaryRegistry() throws -> RootsRegistry {
        try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
    }

    private static func occurrences(of phrase: String, in text: String) -> Int {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.components(separatedBy: phrase).count - 1
    }

    @Test
    func anAnswerOpensWithTheHeaderAndNamesEveryCheckOnce() async throws {
        let repository = try MCPTestRepo.make()

        let (text, refused) = try await CheckupCommand.parse(["--root", repository.path]).answer(registry: Self.temporaryRegistry())
        let lines = text.split(separator: "\n").map(String.init)

        #expect(!refused)
        #expect(lines.first?.hasPrefix("tree: ") == true)
        #expect(lines.dropFirst().first == "checkup: working tree vs HEAD — staged, unstaged and untracked changes · nothing found over 0 changed files")
        let checks = try #require(lines.first { $0.hasPrefix("checked: ") || $0.hasPrefix("not checked: ") })
        for check in CheckupCheck.allCases {
            #expect(checks.components(separatedBy: check.name).count == 2, "\(check.name) is not named exactly once")
        }
        #expect(checks.hasPrefix("checked: callers, exposure · not checked: "))
    }

    @Test
    func anUnknownRangeIsRefusedInCheckupsNameUnderTheHeader() async throws {
        let repository = try MCPTestRepo.make()

        let (text, refused) = try await CheckupCommand.parse(["nosuchrev", "--root", repository.path]).answer(registry: Self.temporaryRegistry())
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(refused)
        #expect(lines.first?.hasPrefix("tree: ") == true)
        #expect(lines.dropFirst().first?.hasPrefix("swift-sure checkup: `nosuchrev` does not name a commit in this repository") == true)
    }

    @Test
    func aRefusedRangeExitsNonzeroAndAnAnswerExitsZero() async throws {
        let repository = try MCPTestRepo.make()
        let registry = try Self.temporaryRegistry()
        var refusing = try CheckupCommand.parse(["HEAD..", "--root", repository.path])
        refusing.registry = { registry }
        var answering = try CheckupCommand.parse(["--root", repository.path])
        answering.registry = { registry }

        await #expect(throws: ExitCode(1)) {
            try await refusing.run()
        }
        try await answering.run()
    }

    /// A range ending at the commit `HEAD` names reads the content a run recorded only while the tree is clean, untracked files included.
    @Test
    func anUncleanTreeAtHeadPutsTheRecordedRunChecksOnTheRevision() async throws {
        let repository = try MCPTestRepo.make()
        let registry = try Self.temporaryRegistry()

        let clean = try await CheckupCommand.parse(["HEAD..HEAD", "--root", repository.path]).answer(registry: registry).text
        try "struct Extra {}\n".write(to: repository.appendingPathComponent("Sources/App/Extra.swift"), atomically: true, encoding: .utf8)
        let unclean = try await CheckupCommand.parse(["HEAD..HEAD", "--root", repository.path]).answer(registry: registry).text

        #expect(clean.contains("test runs (no run recorded on this content)"))
        #expect(unclean.contains("test runs (1 uncommitted change; a run records the working tree's content)"))
    }

    @Test
    func theStandingStatementIsInTheHelpAndTheAnswersTopicOnceEachAndNotInAnAnswer() async throws {
        let repository = try MCPTestRepo.make()
        let help = SiftCommand.helpMessage(for: CheckupCommand.self)
        let topic = try #require(HelpTopics.topic(named: "answers")).body

        let answer = try await CheckupCommand.parse(["--root", repository.path]).answer(registry: Self.temporaryRegistry()).text

        #expect(Self.occurrences(of: Self.statement, in: help) == 1)
        #expect(Self.occurrences(of: Self.statement, in: topic) == 1)
        #expect(Self.occurrences(of: Self.statement, in: answer) == 0)
    }
}
