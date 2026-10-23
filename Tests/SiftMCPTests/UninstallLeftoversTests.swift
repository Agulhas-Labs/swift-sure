//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// What an install leaves beside the parts the uninstall already takes out: the `sift` link `install.sh` makes beside the binary, and the run ledgers under a recorded repository's git common directory.
@Suite(.temporaryDirectories)
struct UninstallLeftoversTests {
    private typealias Fixture = UninstallCommandTests

    /// A directory holding a `swift-sure` binary, with `sift` beside it made by `place`.
    private static func binary(_ place: (URL, URL) throws -> Void) throws -> URL {
        let directory = try TemporaryDirectory.make("uninstall-leftovers-bin")
        let binary = directory.appendingPathComponent("swift-sure")
        try "binary".write(to: binary, atomically: true, encoding: .utf8)
        try place(directory.appendingPathComponent("sift"), directory)
        return binary
    }

    @Test
    func aSiftLinkToTheBinaryJoinsTheRmLine() throws {
        let binary = try Self.binary { link, _ in
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "swift-sure")
        }
        let directory = binary.deletingLastPathComponent().path

        let line = BinaryRemoval.line(for: binary.path)

        #expect(line == "rm \(directory)/swift-sure \(directory)/sift — a running binary does not delete itself")
    }

    @Test
    func aSiftLinkToAnotherFileIsLeftOutOfTheRmLine() throws {
        let binary = try Self.binary { link, directory in
            let other = directory.appendingPathComponent("other-sift")
            try "theirs".write(to: other, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: other.path)
        }

        let line = BinaryRemoval.line(for: binary.path)

        #expect(line == "rm \(binary.path) — a running binary does not delete itself")
    }

    @Test
    func aSiftFileIsLeftOutOfTheRmLine() throws {
        let binary = try Self.binary { file, _ in
            try "theirs".write(to: file, atomically: true, encoding: .utf8)
        }

        let line = BinaryRemoval.line(for: binary.path)

        #expect(line == "rm \(binary.path) — a running binary does not delete itself")
    }

    @Test
    func runAsTheSiftLinkTheRmLineNamesTheBinaryToo() throws {
        let binary = try Self.binary { link, _ in
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "swift-sure")
        }
        let directory = binary.deletingLastPathComponent().path

        let line = BinaryRemoval.line(for: directory + "/sift")

        #expect(line == "rm \(directory)/sift \(directory)/swift-sure — a running binary does not delete itself")
    }

    @Test
    func runAsASiftFileTheRmLineNamesTheSwiftSureLinkToIt() throws {
        let directory = try TemporaryDirectory.make("uninstall-leftovers-bin").path
        try "binary".write(toFile: directory + "/sift", atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: directory + "/swift-sure", withDestinationPath: "sift")

        let line = BinaryRemoval.line(for: directory + "/sift")

        #expect(line == "rm \(directory)/sift \(directory)/swift-sure — a running binary does not delete itself")
    }

    /// The recorded repository made a git repository, with a run ledger where the tool writes one: `<common-dir>/swift-sure/proved-runs.json`.
    private static func ledgered(_ installed: Fixture.Installed, sourceLocation: SourceLocation = #_sourceLocation) throws -> (directory: String, exclude: URL) {
        try RunWithoutCommandTests.git(["init", "-q"], in: installed.recorded)
        let common = try RunWithoutCommandTests.git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: installed.recorded)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = CanonicalPath.of(installed.recorded.path)
        try #require(CanonicalPath.of(common) == repository + "/.git", "the repository is not the one this test made: \(common)", sourceLocation: sourceLocation)
        let directory = repository + "/.git/swift-sure"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "{}".write(toFile: directory + "/proved-runs.json", atomically: true, encoding: .utf8)
        let exclude = URL(fileURLWithPath: repository + "/.git/info/exclude")
        try "# theirs\n.swift-sure/\n".write(to: exclude, atomically: true, encoding: .utf8)
        return (directory, exclude)
    }

    @Test
    func purgeDeletesARecordedRepositorysRunLedgersAndLeavesItsExcludeFile() throws {
        let installed = try Fixture.install()
        let (directory, exclude) = try Self.ledgered(installed)
        let before = try Data(contentsOf: exclude)

        let lines = try Fixture.uninstall(installed, ["--purge"], remover: Fixture.ServerRemover())

        #expect(!FileManager.default.fileExists(atPath: directory))
        #expect(lines.contains("purged: \(directory)"), "\(lines)")
        #expect(try Data(contentsOf: exclude) == before)
    }

    @Test
    func withoutPurgeARecordedRepositorysRunLedgersAreListed() throws {
        let installed = try Fixture.install()
        let (directory, _) = try Self.ledgered(installed)

        let lines = try Fixture.uninstall(installed, remover: Fixture.ServerRemover())

        #expect(FileManager.default.fileExists(atPath: directory + "/proved-runs.json"))
        #expect(lines.contains("left: \(directory)"), "\(lines)")
        #expect(lines.contains { $0.hasSuffix("the usage and run logs, and the run proofs the ledgers record, are gone for good") }, "\(lines)")
    }

    @Test
    func theVerdictCountsPurgedRunLedgersApartFromTheCaches() throws {
        let installed = try Fixture.install()
        _ = try Self.ledgered(installed)

        let lines = try Fixture.uninstall(installed, ["--purge"], remover: Fixture.ServerRemover())

        #expect(lines.first == "uninstall: removed 10 registrations, purged 3 .swift-sure directories and 1 run-ledger directory, deleted the settings backup")
    }

    @Test
    func aFileAtAnEarlierLedgerSpellingIsPassedOver() throws {
        let installed = try Fixture.install()
        let (directory, _) = try Self.ledgered(installed)
        let theirs = URL(fileURLWithPath: directory).deletingLastPathComponent().appendingPathComponent("sift").path
        try "another tool's".write(toFile: theirs, atomically: true, encoding: .utf8)

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], remover: Fixture.ServerRemover())

        #expect(status == 0, "\(lines)")
        #expect(try String(contentsOfFile: theirs, encoding: .utf8) == "another tool's")
        #expect(lines.contains { $0.contains(theirs) } == false, "\(lines)")
        #expect(lines.contains("purged: \(directory)"), "\(lines)")
    }
}
