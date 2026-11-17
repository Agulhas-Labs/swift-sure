//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// An explicit `sed -n` window is answered only where its answer spares more than the identical re-run is expected to cost, weighed as a `Read` window is but with the share `sed -n` windows measured: ``WholeReadWorth/sedWindowReRunShare``.
@Suite(.temporaryDirectories)
struct SedWindowWorthTests {
    // MARK: - The inequality

    /// A window of 2,000 tokens and an answer of 700 at the default context (a turn of 720): `1300 > 0.15 · 2720 = 408` keeps the answer, and `1300 < 0.48 · 2720 = 1305.6` would not.
    @Test
    func theSedShareIsNotTheReadShare() {
        #expect(WholeReadWorth.isReadWindowWorthTheTurn(windowBytes: 8000, answerBytes: 2800, contextTokens: nil, reRunShare: WholeReadWorth.sedWindowReRunShare))
        #expect(!WholeReadWorth.isReadWindowWorthTheTurn(windowBytes: 8000, answerBytes: 2800, contextTokens: nil))
        #expect(WholeReadWorth.sedWindowReRunShare == 0.15)
    }

    /// Each tool names its share, and a tool that is neither has none.
    @Test
    func eachToolPricesItsWindowsWithItsOwnShare() {
        let sed = LineWindow(stages: [["sed", "-n", "1,5p", "A.swift"]])
        let head = LineWindow(stages: [["head", "-5", "A.swift"]])

        #expect(WholeReadWorth.reRunShare(of: ["tool_name": "Read"], windows: [sed]) == WholeReadWorth.readWindowReRunShare)
        #expect(WholeReadWorth.reRunShare(of: ["tool_name": "Bash"], windows: [sed, sed]) == WholeReadWorth.sedWindowReRunShare)
        #expect(WholeReadWorth.reRunShare(of: ["tool_name": "Bash"], windows: [head]) == nil)
        #expect(WholeReadWorth.reRunShare(of: ["tool_name": "Bash"], windows: [sed, head]) == nil)
        #expect(WholeReadWorth.reRunShare(of: ["tool_name": "Grep"], windows: [sed]) == nil)
    }

    // MARK: - Through the hook, with a stubbed answer

    /// A file of exactly 100 lines on disk, so the share a window prints is its line count in hundredths.
    private static func hundredLineFile() throws -> URL {
        let directory = try TemporaryDirectory.make("sed-window-worth")
        let file = directory.appendingPathComponent("Depot.swift")
        try ((1 ... 100).map { "// line \($0)" }.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// A shell `command` as the hook receives it, in a context of `tokens` where given.
    private static func bash(_ command: String, context tokens: Int? = nil) -> [String: Any] {
        var payload: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": command], "session_id": "s1", "tool_use_id": "toolu_sed_window"]
        if let tokens {
            payload[ContextSize.replayKey] = tokens
        }
        return payload
    }

    /// The hook's printed decision and verdict for `payload`, every lookup answered with a digest of `served` bytes standing in for `source`.
    private static func judged(_ payload: [String: Any], in directory: URL, answers served: Int, of source: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> (json: String?, verdict: PreToolUseCommand.Verdict) {
        let scratch = try TemporaryDirectory.make("sed-window-worth-hook")
        let suppressions = SuppressionLog(fileURL: scratch.appendingPathComponent("suppressions.jsonl"))
        let command = (payload["tool_input"] as? [String: Any])?["command"] as? String
        let lookup = try #require(PreToolUseCommand.lookup(command: command, payload: payload, in: directory.path, noting: suppressions, couldAnswer: { _, _ in true }), sourceLocation: sourceLocation)
        let target = directory.appendingPathComponent("Depot.swift").path
        let reason = "swift-sure answered this with `digest \(target)` instead of running it\(InPlaceAnswer.openingSuffix)\n\nbody"
        let call = InPlaceAnswerer.Call(tool: "digest", target: target, bytes: AnswerBytes(served: served, source: source), intercepted: .window)
        let answered = InPlaceAnswerer.Outcome.answered(InPlaceAnswerer.Answered(reason: reason, calls: [call], root: directory.path, milliseconds: 1, wholeRead: call.bytes))
        return PreToolUseCommand.outcome(
            to: lookup,
            session: "s1",
            context: AdviceContext.resolve(sessionID: "s1", transcriptPath: nil, agentID: nil),
            payload: payload,
            command: command,
            cwd: directory.path,
            ledger: AdviceLedger(directory: scratch.appendingPathComponent("advice")),
            usage: UsageLog(fileURL: scratch.appendingPathComponent("usage.jsonl")),
            suppressions: suppressions,
            answerer: { _, _, _ in answered }
        )
    }

    /// A window of 2,000 tokens answered with 1,500, in a context of 200,000 (a turn of 3,200): it spares 500, under `0.15 · 5200 = 780`.
    @Test
    func aSedWindowSparingLessThanItsReRunIsLetThrough() throws {
        let file = try Self.hundredLineFile()

        let judged = try Self.judged(Self.bash("sed -n 1,40p Depot.swift", context: 200_000), in: file.deletingLastPathComponent(), answers: 6000, of: 8000)

        #expect(judged.verdict.token == "allowed" && judged.verdict.rule == "notWorthTheTurn", "\(judged.verdict.line)")
        #expect(judged.json == nil)
    }

    /// The same window and answer at the default context (a turn of 720) spare 500, over `0.15 · 2720 = 408`, and are answered.
    @Test
    func theSameSedWindowAtTheDefaultContextIsAnswered() throws {
        let file = try Self.hundredLineFile()

        let judged = try Self.judged(Self.bash("sed -n 1,40p Depot.swift"), in: file.deletingLastPathComponent(), answers: 6000, of: 8000)

        #expect(judged.verdict.token == "in-place", "\(judged.verdict.line)")
        #expect(judged.json?.contains("swift-sure answered this with") == true)
    }

    /// Two windows on one file in one line are weighed on the windows' total.
    @Test(arguments: [(200_000, "allowed"), (nil, "in-place")] as [(Int?, String)])
    func severalSedWindowsOnOneFileAreWeighedOnTheirTotal(tokens: Int?, token: String) throws {
        let file = try Self.hundredLineFile()

        let judged = try Self.judged(Self.bash("sed -n 1,20p Depot.swift; sed -n 41,60p Depot.swift", context: tokens), in: file.deletingLastPathComponent(), answers: 6000, of: 8000)

        #expect(judged.verdict.token == token, "\(judged.verdict.line)")
        #expect(token == "in-place" || judged.verdict.rule == "notWorthTheTurn", "\(judged.verdict.line)")
    }

    /// An answer sparing between 0.15 and 0.48 of the re-run is answered for `sed -n`: 1,300 tokens spared at the default context.
    @Test
    func aSavingBetweenTheTwoSharesIsAnsweredForSed() throws {
        let file = try Self.hundredLineFile()

        let judged = try Self.judged(Self.bash("sed -n 1,40p Depot.swift"), in: file.deletingLastPathComponent(), answers: 2800, of: 8000)

        #expect(judged.verdict.token == "in-place", "\(judged.verdict.line)")
    }

    // MARK: - Through the real answerer

    /// The hook's verdict line for `payload`, answered by the real answerer against `root`.
    private static func decide(_ made: @escaping @Sendable () -> [String: Any], in root: URL) async throws -> String {
        let backoff = try InPlaceAnswerTests.backoff()
        let advice = try TemporaryDirectory.make("advice")
        let usage = try TemporaryDirectory.make("usage").appendingPathComponent("usage.jsonl")
        let log = try TemporaryDirectory.make("suppressions").appendingPathComponent("suppressions.jsonl")
        return await InPlaceAnswerTests.onItsOwnThread { () -> String in
            let payload = made()
            let command = (payload["tool_input"] as? [String: Any])?["command"] as? String
            guard let lookup = PreToolUseCommand.lookup(command: command, payload: payload, in: root.path, noting: SuppressionLog(fileURL: log), couldAnswer: { _, _ in true }) else {
                return "no lookup"
            }
            return PreToolUseCommand.outcome(
                to: lookup,
                session: "s1",
                context: AdviceContext.resolve(sessionID: "s1", transcriptPath: nil),
                payload: payload,
                command: command,
                cwd: root.path,
                ledger: AdviceLedger(directory: advice),
                usage: UsageLog(fileURL: usage),
                suppressions: SuppressionLog(fileURL: log),
                answerer: { match, gone, _ in InPlaceAnswerer.answer(match, serverGone: gone, timeBudget: InPlaceAnswerTests.roomy, backoff: backoff) },
                serverPresence: { _, _ in false }
            ).verdict.line
        }
    }

    /// A window too small to pay for a turn in a large context is settled before its answer is built: 3 lines of `Depot` against a turn of 3,200 tokens.
    @Test
    func aTinySedWindowInALargeContextIsSettledBeforeItsAnswer() async throws {
        let root = try await WorthAnsweringFixture.repository()

        let verdict = try await Self.decide({ Self.bash("sed -n 3,5p Sources/App/Depot.swift", context: 200_000) }, in: root)

        #expect(verdict == "allowed\t\tnotWorthTheTurn", "\(verdict)")
    }
}
