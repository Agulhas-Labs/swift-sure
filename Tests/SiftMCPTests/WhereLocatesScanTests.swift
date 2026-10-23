//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// A Bash line of nothing but `swift-sure where`/`swift-sure search` lookups locates the files its output lists, in the audit's scan as in the replay and the live hook, and a line that could have been answered from another repository, or printed anything else, locates nothing.
@Suite(.temporaryDirectories) struct WhereLocatesScanTests {
    /// A `where` answer as the CLI prints it, declaring the fixture's type.
    private static var whereAnswer: String {
        "where Alpha\ndeclarations (1):\n  App.Alpha — struct — struct Alpha — Sources/App/Alpha.swift:2-5\n"
    }

    /// A `search` answer as the CLI prints it, one file heading and one match under it.
    private static var searchAnswer: String {
        "search kind:struct\n1 declaration(s) in 1 file(s) — scanned 1 file(s)\n\nSources/App/Alpha.swift:\n  2  struct Alpha\n"
    }

    /// Lines of nothing but lookups of the caller's repository, each at most narrowed by a filter reading only the pipe, answer from it.
    @Test(arguments: [
        "swift-sure where Alpha",
        "swift-sure where Alpha | head -5",
        "swift-sure where Alpha 2>&1 | head -n 20",
        "swift-sure search 'kind:struct' | grep Alpha | sort -u",
        "swift-sure where Alpha && swift-sure search kind:struct",
        "swift-sure where Alpha | tail -3 | uniq -c",
    ])
    func aLineOfOnlyLookupsAnswersFromTheCallersRepository(command: String) throws {
        let here = try MCPTestRepo.make()
        let source = try #require(ShellAnswerSource.of(command: command, cwd: here.path))

        #expect(source.root == CallerRoot.root(forCallerIn: here.path))
    }

    /// Anything that could move the lookup to another directory or print beside it credits nothing: a directory change, a subshell or group, a substitution or variable, another command, a filter handed a file of its own, a lookup as of another revision, or a subcommand whose answer is not a list of located files.
    @Test(arguments: [
        "cd /elsewhere && swift-sure where Alpha",
        "pushd /elsewhere && swift-sure where Alpha",
        "(cd /elsewhere && swift-sure where Alpha)",
        "{ swift-sure where Alpha; }",
        "swift-sure where $(cat name.txt)",
        "swift-sure where --root $ROOT Alpha",
        "swift-sure where Alpha; grep -r '^$' Sources",
        "swift-sure where Alpha && ls",
        "swift-sure where Alpha | grep Alpha Sources/App/Alpha.swift",
        "swift-sure where Alpha | grep -r Alpha",
        "swift-sure where Alpha | sed s/a/b/",
        "swift-sure where Alpha | head < other.txt",
        "swift-sure where --at HEAD~1 Alpha",
        "swift-sure digest Alpha",
        "swift-sure where Alpha --root /",
    ])
    func aLineThatCouldAnswerFromElsewhereOrPrintBesideCreditsNothing(command: String) throws {
        let here = try MCPTestRepo.make()

        #expect(ShellAnswerSource.of(command: command, cwd: here.path) == nil)
    }

    /// A `--root` naming another repository answers from that repository, which the CLI opens exactly so.
    @Test
    func aRootNamingAnotherRepositoryAnswersFromIt() throws {
        let here = try MCPTestRepo.make()
        let other = try MCPTestRepo.make()

        #expect(ShellAnswerSource.of(command: "swift-sure where --root \(other.path) Alpha", cwd: here.path)?.root == CallerRoot.root(forCallerIn: other.path))
    }

    /// A `--root` written after a redirection is lost to `cliLookups`'s own cut, so it used to fall back to the caller's repository even though the CLI, reading the whole line, answered from the one the redirect's word named; it now credits nothing.
    @Test
    func aRootAfterARedirectionCreditsNothing() throws {
        let here = try MCPTestRepo.make()
        let other = try MCPTestRepo.make()
        for command in [
            "swift-sure where Alpha 2>&1 --root \(other.path)",
            "swift-sure where Alpha 2>/dev/null --root \(other.path)",
            "swift-sure search 'kind:struct' 2>&1 --root \(other.path)",
        ] {
            #expect(ShellAnswerSource.of(command: command, cwd: here.path) == nil)
        }
    }

    /// A redirection at the end of the line, past the `--root` it names, has nothing riding after its own destination — the CLI still answers from that repository, and so does this.
    @Test
    func aRedirectAfterTheRootStillCreditsIt() throws {
        let here = try MCPTestRepo.make()
        let other = try MCPTestRepo.make()

        #expect(ShellAnswerSource.of(command: "swift-sure where Alpha --root \(other.path) 2>&1", cwd: here.path)?.root == CallerRoot.root(forCallerIn: other.path))
    }

    /// A repeated `--root` reads first-wins here where the CLI's own parser reads last-wins; crediting either one risks the wrong repository, so a second `--root` credits nothing at all.
    @Test
    func aRepeatedRootCreditsNothing() throws {
        let here = try MCPTestRepo.make()
        let other = try MCPTestRepo.make()

        #expect(ShellAnswerSource.of(command: "swift-sure where Alpha --root \(here.path) --root \(other.path)", cwd: other.path) == nil)
        #expect(ShellAnswerSource.of(command: "swift-sure where Alpha --root \(other.path) --root \(here.path)", cwd: other.path) == nil)
    }

    /// The disagreement this closes: the hook lets a window of a file a Bash `where` or `search` listed through as the loop working, and the scan counted it cold.
    @Test(arguments: [
        ("swift-sure where Alpha", whereAnswer),
        ("swift-sure search kind:struct | head -20", searchAnswer),
    ])
    func aWindowOfAFileABashLookupListedIsGuided(command: String, output: String) throws {
        let here = try MCPTestRepo.make()
        let lookups = TranscriptFixture.lookups(
            [
                TranscriptFixture.toolUse("Bash", id: "b1", input: ["command": command], cwd: here.path),
                TranscriptFixture.toolResult(id: "b1", isError: false, text: output),
                TranscriptFixture.toolUse("Bash", id: "w1", input: ["command": "sed -n 2,4p Sources/App/Alpha.swift"], cwd: here.path),
            ],
            belowFloor: { _ in false }
        )

        #expect(lookups == [.indexed, .guided(file: "Sources/App/Alpha.swift")])
    }

    /// The same answer behind a directory change, or beside another command, or on a line that failed, locates nothing: the window stays cold.
    @Test(arguments: [
        ("cd /elsewhere && swift-sure where Alpha", false),
        ("swift-sure search kind:enum; grep -r '^$' Sources", false),
        ("swift-sure where Alpha", true),
    ])
    func aBashLookupTheScanCannotPinLocatesNothing(command: String, failed: Bool) throws {
        let here = try MCPTestRepo.make()
        let lookups = TranscriptFixture.lookups(
            [
                TranscriptFixture.toolUse("Bash", id: "b1", input: ["command": command], cwd: here.path),
                TranscriptFixture.toolResult(id: "b1", isError: failed, text: Self.whereAnswer + Self.searchAnswer),
                TranscriptFixture.toolUse("Bash", id: "w1", input: ["command": "sed -n 2,4p Sources/App/Alpha.swift"], cwd: here.path),
            ],
            belowFloor: { _ in false }
        )

        #expect(lookups.last == .cold(file: "Sources/App/Alpha.swift", missed: nil))
    }

    /// The replay hands each answered index call's text to the hook and to the one it is compared against, which is all a `where` or `search` answer can locate anything by there.
    @Test
    func theReplayHandsEachAnsweredCallsTextToBothHooks() throws {
        let root = try TemporaryDirectory.make("root")
        let hook = RecordingHook(indexCalls: true)
        let against = RecordingHook(indexCalls: true)
        let transcript = try TemporaryDirectory.make("projects").appendingPathComponent("replayed-session.jsonl")
        let lines = [
            TranscriptFixture.toolUse("mcp__swift-sure__where", id: "m1", input: ["symbol": "Alpha"], cwd: root.path),
            TranscriptFixture.toolResult(id: "m1", isError: false, text: Self.whereAnswer),
            TranscriptFixture.toolUse("Bash", id: "b1", input: ["command": "swift-sure search kind:struct"], cwd: root.path),
            TranscriptFixture.toolResult(id: "b1", isError: false, text: Self.searchAnswer),
        ]
        try Data(lines.joined(separator: [0x0A])).write(to: transcript)

        let probes = ReplayProbes(since: nil, until: nil, timeZone: .current, belowFloor: { _ in false }, couldAnswer: { _, _ in true }, memberExists: { _, _, _ in true })
        _ = TranscriptReplay.replay(transcript, session: transcript, isSubagent: false, probes: probes, hook: hook, against: against)

        #expect(hook.answers == [Self.whereAnswer, Self.searchAnswer])
        #expect(against.answers == [Self.whereAnswer, Self.searchAnswer])
    }
}
