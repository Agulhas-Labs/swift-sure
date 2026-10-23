//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// A linter's subcommands that do not lint print the answer itself, so they are no lint run.
struct LinterQuestionRecognitionTests {
    @Test(arguments: [
        ["swiftlint", "version"], ["swiftlint", "--version"], ["swiftlint", "rules"], ["swiftlint", "reporters"],
        ["swiftlint", "help"], ["swiftlint", "--help"], ["swiftlint", "docs"], ["swiftlint", "generate-docs"],
        ["/usr/local/bin/swiftlint", "version"], ["swiftlint", "rules", "--path", "Sources"],
        ["swiftlint", "-h"], ["swiftlint", "-help"], ["swiftlint", "-version"],
        ["swiftlint", "lint", "--version"], ["swiftlint", "lint", "--path", "Sources", "-version"],
    ])
    func aNonLintSubcommandIsNotFiltered(arguments: [String]) {
        #expect(RunCommandKind.recognize(arguments) == .unrecognized)
    }

    @Test
    func aConfiguredLintersQuestionIsNotFilteredEither() {
        #expect(RunCommandKind.recognize(["swiftformat", "--version"], linters: ["swiftformat"]) == .unrecognized)
        #expect(RunCommandKind.recognize(["swiftformat", "--help"], linters: ["swiftformat"]) == .unrecognized)
        #expect(RunCommandKind.recognize(["swiftformat", "Sources", "--lint"], linters: ["swiftformat"]) == .linter)
    }

    @Test(arguments: [
        ["swiftlint"], ["swiftlint", "lint"], ["swiftlint", "lint", "--strict"], ["swiftlint", "lint", "--help"],
        ["swiftlint", "lint", "--path", "Sources", "--help"], ["swiftlint", "--path", "Sources"],
    ])
    func aLintRunKeepsItsDigest(arguments: [String]) {
        #expect(RunCommandKind.recognize(arguments) == .linter)
    }

    @Test
    func aConfiguredLinterGetsOnlyTheFlagsNotSwiftlintsWords() {
        let linters = Set(["swiftformat"])
        for flag in ["-h", "-help", "-version"] {
            #expect(RunCommandKind.recognize(["swiftformat", flag], linters: linters) == .unrecognized)
        }
        for word in ["docs", "rules", "version", "help", "reporters"] {
            #expect(RunCommandKind.recognize(["swiftformat", word, "--lint"], linters: linters) == .linter)
        }
    }
}
