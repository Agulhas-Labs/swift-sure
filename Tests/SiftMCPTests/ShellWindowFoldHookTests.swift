//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// The hook answers a shell window of a file nothing in the context has located with the lines it prints, comment runs folded, or lets it through; never with a digest.
///
/// A window of a located file goes the way it always did; a `Read` window is judged as its shell form (`ReadWindowFoldTests`).
@Suite(.temporaryDirectories)
struct ShellWindowFoldHookTests {
    /// The commented file's path in the repository.
    static var commented: String {
        "Sources/App/Commented.swift"
    }

    /// The code-only file's path in the repository.
    static var plain: String {
        "Sources/App/Plain.swift"
    }

    /// A repository holding `Commented.swift`, fifty members under three doc-comment lines each, and `Plain.swift`, two hundred lines of code and no comment.
    private static func repository() throws -> URL {
        let root = try MCPTestRepo.make(declaring: "Alpha")
        let members = (1 ... 50).map { index in
            "    /// Member \(index) explains what it counts, in words.\n    /// It says so at length, so its comment outweighs its code.\n    /// And a third line closes the run.\n    func stock\(index)() -> Int { \(index) }"
        }
        try ("struct Commented {\n" + members.joined(separator: "\n") + "\n}\n")
            .write(to: root.appendingPathComponent(commented), atomically: true, encoding: .utf8)
        let lines = (1 ... 198).map { "    let value\($0) = \($0)" }
        try ("struct Plain {\n" + lines.joined(separator: "\n") + "\n}\n")
            .write(to: root.appendingPathComponent(plain), atomically: true, encoding: .utf8)
        return root
    }

    /// The hook's decision on a Bash `command`, or on a call of `tool` with `input`, run from `root` in `context`.
    private static func decide(_ command: String? = nil, tool: String = "Bash", input: [String: Any]? = nil, in root: URL, context: Context) async throws -> (json: String?, verdict: PreToolUseCommand.Verdict) {
        let backoff = try InPlaceAnswerTests.backoff()
        let payloadData = try JSONSerialization.data(withJSONObject: ["tool_name": tool, "tool_input": input ?? ["command": command ?? ""], "session_id": context.session, "tool_use_id": "toolu_fold"])
        let usage = UsageLog(fileURL: context.usage)
        let ledger = context.ledger
        let suppressions = context.suppressions
        let session = context.session
        let directory = root.path
        let decided = await InPlaceAnswerTests.onItsOwnThread { () -> Decided in
            let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]
            let outcome = PreToolUseCommand.decided(
                command: nil,
                payload: payload,
                cwd: directory,
                session: session,
                context: AdviceContext.resolve(sessionID: session, transcriptPath: nil),
                answerer: { InPlaceAnswerer.answer($0, serverGone: $1, timeBudget: $2, backoff: backoff) },
                ledger: ledger,
                usage: usage,
                suppressions: suppressions,
                couldAnswer: { _, _ in true }
            )
            return Decided(json: outcome.json, token: outcome.verdict.token, call: outcome.verdict.call, rule: outcome.verdict.rule, reason: outcome.verdict.reason)
        }
        return (decided.json, PreToolUseCommand.Verdict(token: decided.token, call: decided.call, rule: decided.rule, reason: decided.reason))
    }

    /// A commented window, alone or numbered by any of the stages the spec lists, is answered with its own lines, the comment runs folded.
    @Test(arguments: [
        ("sed -n '1,120p' \(commented)", "window \(commented):1-120"),
        ("cat -n \(commented) | sed -n 1,120p", "window \(commented):1-120"),
        ("sed -n 1,120p \(commented) | awk '{print NR+0\": \"$0}'", "window \(commented):1-120"),
        ("head -150 \(commented) | nl -ba", "window \(commented):1-150"),
    ])
    func aCommentedWindowIsAnsweredWithItsCommentsFolded(command: String, call: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.verdict.line == "in-place\t\(call)\tcommentsFolded", "\(command)")
        let reason = try #require(decided.verdict.reason)
        #expect(reason.hasPrefix("swift-sure answered `\(call)` instead of running it: "), "\(reason.prefix(200))")
        #expect(reason.contains(": // … 3 comment lines\n"))
        #expect(decided.json?.contains("\"permissionDecision\":\"deny\"") == true || decided.json?.contains("\"permissionDecision\" : \"deny\"") == true)
        // A fold is never a digest, and locates nothing.
        #expect(!reason.contains("digest "))
        #expect(context.ledger.digests(session: AdviceContext.resolve(sessionID: context.session, transcriptPath: nil).key).isEmpty)
    }

    /// The `cat -n … | sed -n a,bp` window the whole-file digest once answered goes to the fold, never to a digest.
    @Test
    func aNumberedCatWindowIsNeverAnsweredWithADigest() async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide("cat -n \(Self.commented) | sed -n 95,180p", in: root, context: context)

        #expect(decided.verdict.call?.hasPrefix("digest") != true)
        #expect(decided.verdict.line == "in-place\twindow \(Self.commented):95-180\tcommentsFolded")
    }

    /// A window the fold would spare too little of is let through as `notSmaller`, logged against the call.
    @Test
    func aCodeOnlyWindowIsLetThroughAsNotSmaller() async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide("sed -n 1,100p \(Self.plain)", in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.line == "allowed\t\tnotSmaller")
        #expect(context.logged.contains { $0["rule"] as? String == "answerWithheld" && $0["symbol"] as? String == "notSmaller" && $0["call"] as? String == "toolu_fold" })
    }

    /// A window beside any other leg, or joined by `||`, is let through whole as `windowBeside`, logged against the call, and spends nothing of the ledger.
    @Test(arguments: [
        "grep -n stock \(commented); sed -n 1,120p \(commented)",
        "sed -n 1,120p \(commented) || cat \(commented)",
        "sed -n 1,120p \(commented) || sed -n 1,60p \(commented)",
        "cd - && sed -n 1,120p \(commented)",
    ])
    func aWindowBesideAnotherLegIsLetThroughAsWindowBeside(command: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.line == "allowed\t\twindowBeside", "\(command)")
        #expect(context.logged.contains { $0["rule"] as? String == "answerWithheld" && $0["symbol"] as? String == "windowBeside" && $0["call"] as? String == "toolu_fold" })
        // The ledger was never asked, so the same line is let through the same way again rather than as a re-run.
        #expect(try await Self.decide(command, in: root, context: context).verdict.line == "allowed\t\twindowBeside")
    }

    /// A statement that prints nothing and that the compound rules reproduce is no leg: the window is folded as if it stood alone, its file read from where a `cd` moved.
    @Test(arguments: [
        "cd Sources/App && sed -n 1,120p Commented.swift",
        "cd Sources; cd App; sed -n 1,120p Commented.swift",
        "X=1; export Y=2; unset Z; set -e; sed -n 1,120p \(commented)",
        "sed -n 1,120p \(commented) || true",
    ])
    func aStatementThatPrintsNothingLeavesTheWindowFolded(command: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.verdict.line == "in-place\twindow \(Self.commented):1-120\tcommentsFolded", "\(command)")
    }

    /// A window's file holding a parse error decides before the leg beside it: no answer could serve that file, so the line is no miss.
    @Test
    func aParseErrorBesideAnotherLegDecidesBeforeWindowBeside() async throws {
        let root = try Self.repository()
        let file = root.appendingPathComponent(Self.commented)
        try (String(contentsOf: file, encoding: .utf8) + "}\n").write(to: file, atomically: true, encoding: .utf8)
        try await SiftEngine(directory: root).ensureFresh()
        let context = try Context()

        let decided = try await Self.decide("grep -n stock \(Self.commented); sed -n 1,120p \(Self.commented)", in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.line == "allowed\t\tparseError")
    }

    /// A `cat` of several files into a window prints lines of the files joined, which the fold never renders: let through as `notExact`, never folded as a window of one of them.
    @Test(arguments: [
        "cat -n \(commented) \(plain) | sed -n 1,120p",
        "cat \(plain) \(commented) | head -150",
    ])
    func aCatOfSeveralFilesIntoAWindowIsNotExact(command: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.line == "allowed\t\tnotExact", "\(command)")
    }

    /// A line of windows with `echo`s between them is folded leg by leg under one answer naming each window.
    @Test
    func windowsBetweenEchoesAreFoldedTogether() async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide("sed -n 1,80p \(Self.commented); echo ---; sed -n 120,200p \(Self.commented)", in: root, context: context)

        #expect(decided.verdict.line == "in-place\twindow \(Self.commented):1-80; window \(Self.commented):120-200\tcommentsFolded")
        #expect(decided.verdict.reason?.contains("\n---\n") == true)
    }

    /// The identical re-run after a fold is allowed by the ledger.
    @Test
    func theIdenticalReRunAfterAFoldIsAllowed() async throws {
        let root = try Self.repository()
        let context = try Context()
        let command = "sed -n 1,120p \(Self.commented)"

        #expect(try await Self.decide(command, in: root, context: context).verdict.token == "in-place")
        #expect(try await Self.decide(command, in: root, context: context).verdict.line == "allowed\t\tledger")
    }

    /// A window of a file the ledger has located goes the way a located window always did: let through, never folded.
    @Test
    func aLocatedFilesWindowIsNotFolded() async throws {
        let root = try Self.repository()
        let context = try Context()
        let key = AdviceContext.resolve(sessionID: context.session, transcriptPath: nil).key
        let repository = try #require(CallerRoot.root(forCallerIn: root.path))
        context.ledger.noteIndexCall(session: key, calls: ["digest \(Self.commented)"], digests: [repository: [Self.commented]])

        let decided = try await Self.decide("sed -n 1,120p \(Self.commented)", in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.token == "allowed")
        #expect(decided.verdict.rule != "commentsFolded")
    }

    /// A fold delivered as the hook's error result is scored as answered in place, as every in-place answer is.
    @Test
    func aFoldDeliveredAsAnErrorIsScoredAsAnsweredInPlace() async throws {
        let root = try Self.repository()
        let context = try Context()
        let file = root.appendingPathComponent(Self.commented).path
        let command = "sed -n 1,120p \(file)"
        let reason = try #require(try await Self.decide(command, in: root, context: context).verdict.reason)

        let lines = [
            TranscriptFixture.toolUse("Bash", id: "t1", input: ["command": command], cwd: root.path),
            TranscriptFixture.toolResult(id: "t1", isError: true, text: "PreToolUse:Bash hook error: " + reason),
        ]
        var state = TranscriptScanState()
        let events = lines.flatMap { TranscriptScan.events(line: $0, state: &state, belowFloor: { _ in false }, couldAnswer: { _, _ in true }) }

        #expect(events.contains {
            if case .answeredInPlace = $0 {
                return true
            }
            return false
        })
        #expect(TranscriptFixture.tally(lines).indexed == 1)
    }

    /// A line whose every window the usage log or the ledger locates gets the reading it had before the fold: the usage log's located windows are dropped, the rest is weighed by every gate, and each rule is logged once.
    @Test
    func aLineTheLedgerLocatesKeepsTheReadingItHadBeforeTheFold() async throws {
        let root = try Self.repository()
        let repository = try #require(CallerRoot.root(forCallerIn: root.path))
        // A fresh context whose ledger holds the whole digest of the commented file.
        let ledgerLocated = {
            let context = try Context()
            let key = AdviceContext.resolve(sessionID: context.session, transcriptPath: nil).key
            context.ledger.noteIndexCall(session: key, calls: ["digest \(Self.commented)"], digests: [repository: [Self.commented]])
            return context
        }

        // The usage log locates one window and the ledger the other: both are dropped, never answered with a digest.
        let located = try await Self.judged("sed -n 1,60p \(Self.plain); sed -n 1,120p \(Self.commented)", in: root, context: ledgerLocated(), usageLocated: [Self.plain])
        #expect(located.line == "allowed\t\tlocatedWindow")
        #expect(located.rules == ["locatedWindow"])

        // A grep for a name no index declares, beside a window the ledger locates, is withheld as it was before the fold.
        let grep = try await Self.judged("grep -n gizmo \(Self.plain); sed -n 1,120p \(Self.commented)", in: root, context: ledgerLocated(), declared: false)
        #expect(grep.line == "allowed\t\tunknownName")
        #expect(grep.rules == ["unknownName"])
    }

    /// A `set` or `export` that prints the shell's variables or options is a leg beside the window, which is let through whole.
    @Test(arguments: ["set; sed -n 1,120p \(commented)", "export -p; sed -n 1,120p \(commented)", "set -o; sed -n 1,120p \(commented)"])
    func aSetThatPrintsIsALegBesideTheWindow(command: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.line == "allowed\t\twindowBeside", "\(command)")
    }

    /// A window whose stages carry a `2>/dev/null` or `2>&1` is the window without them: folded, never answered with a digest, its file the stage's operand rather than the redirection.
    @Test(arguments: [
        ("sed -n 1,120p \(commented) 2>/dev/null", "window \(commented):1-120"),
        ("head -150 \(commented) 2>/dev/null", "window \(commented):1-150"),
        ("sed -n 1,120p \(commented) 2>&1", "window \(commented):1-120"),
        ("cat -n \(commented) 2>/dev/null | sed -n 1,120p", "window \(commented):1-120"),
        ("cd Sources/App && sed -n 1,120p Commented.swift 2>/dev/null", "window \(commented):1-120"),
        ("sed -n 1,120p \(commented) | cat -n 2>/dev/null", "window \(commented):1-120"),
    ])
    func aRedirectedWindowIsFolded(command: String, call: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.verdict.line == "in-place\t\(call)\tcommentsFolded", "\(command)")
    }

    /// A code-only window carrying a redirection is let through as `notSmaller`, as it is without one.
    @Test(arguments: ["sed -n 1,100p \(plain) 2>/dev/null", "head -100 \(plain) 2>&1"])
    func aRedirectedCodeOnlyWindowIsNotSmaller(command: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.line == "allowed\t\tnotSmaller", "\(command)")
    }

    /// A numbering stage before a later filter numbers lines the fold cannot render: let through as `notExact`, never folded with its numbers dropped.
    @Test(arguments: [
        "sed -n 1,150p \(commented) | cat -n | head -100",
        "cat \(commented) | cat -n | sed -n 1,150p",
        "head -150 \(commented) | cat -n | tail -120",
        "sed -n 1,150p \(commented) | nl -ba | head -120",
        "sed -n 1,150p \(commented) | nl | head -120",
    ])
    func aNumberingStageBeforeAFilterIsNotExact(command: String) async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(command, in: root, context: context)

        #expect(decided.json == nil)
        #expect(decided.verdict.line == "allowed\t\tnotExact", "\(command)")
    }

    /// A shell window reaching the answer the fold did not claim, a shape it does not model, is let through as `notExact`, never answered with a digest; a window reaching every line of its file is still a whole read.
    @Test(arguments: [
        ("sed -n 10,190p \(commented)", "allowed\t\tnotExact"),
        ("sed -n 1,500p \(commented)", nil),
    ])
    func aWindowTheFoldDidNotClaimIsNotExact(command: String, line: String?) async throws {
        let root = try Self.repository()
        let context = try Context()
        let match = try #require(InPlaceShape.match(forShell: command, in: root.path))
        let lookup = PreToolUseCommand.Lookup(key: command, suggestion: IndexSuggestion(call: "digest \(Self.commented)", yields: "every member"), textSearch: nil, inPlace: match, rule: "ShellAdvice")
        let backoff = try InPlaceAnswerTests.backoff()
        let (ledger, suppressions, usage, session, directory) = (context.ledger, SuppressionLog(fileURL: context.suppressions), UsageLog(fileURL: context.usage), context.session, root.path)

        let decided = await InPlaceAnswerTests.onItsOwnThread { () -> Decided in
            let outcome = PreToolUseCommand.outcome(
                to: lookup,
                session: session,
                context: AdviceContext.resolve(sessionID: session, transcriptPath: nil),
                payload: ["session_id": session, "tool_use_id": "toolu_fold"],
                cwd: directory,
                ledger: ledger,
                usage: usage,
                suppressions: suppressions,
                answerer: { InPlaceAnswerer.answer($0, serverGone: $1, timeBudget: $2, backoff: backoff) }
            )
            return Decided(json: outcome.json, token: outcome.verdict.token, call: outcome.verdict.call, rule: outcome.verdict.rule, reason: outcome.verdict.reason)
        }

        if let line {
            #expect(decided.json == nil)
            #expect(PreToolUseCommand.Verdict(token: decided.token, call: decided.call, rule: decided.rule).line == line)
            #expect(context.logged.contains { $0["rule"] as? String == "answerWithheld" && $0["symbol"] as? String == "notExact" && $0["call"] as? String == "toolu_fold" })
        } else {
            #expect(decided.rule != "notExact")
        }
    }

    /// The hook's verdict line on a Bash `command` run from `root` in `context`, the lookup then its outcome as the live hook decides one, with `usageLocated` held by the usage log's whole digests and every name declared or none, and the rules the suppression log holds afterwards, in order.
    private static func judged(_ command: String, in root: URL, context: Context, usageLocated: [String] = [], declared: Bool = true) async throws -> (line: String, rules: [String]) {
        let backoff = try InPlaceAnswerTests.backoff()
        let repository = CallerRoot.root(forCallerIn: root.path) ?? root.path
        let usage = try DigestedFilesTests.UsageLogFile(usageLocated.map { ["tool": "digest", "target": $0, "root": repository, "ms": 3, "ok": true, "session": context.session, "outBytes": 900, "srcBytes": 12000] })
        defer { usage.cleanup() }
        let payloadData = try JSONSerialization.data(withJSONObject: ["tool_name": "Bash", "tool_input": ["command": command], "session_id": context.session, "tool_use_id": "toolu_fold"])
        let digested = usage.digested
        let (ledger, usageLog, suppressions, session, directory) = (context.ledger, UsageLog(fileURL: context.usage), context.suppressions, context.session, root.path)
        let line = await InPlaceAnswerTests.onItsOwnThread { () -> String in
            let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]
            let advice = AdviceContext.resolve(sessionID: session, transcriptPath: nil)
            let noted = NotedRule()
            let log = SuppressionLog(fileURL: suppressions, noted: noted.record)
            let letThrough = { PreToolUseCommand.Verdict(token: "allowed", rule: noted.last ?? "noLookup").line }
            guard let lookup = PreToolUseCommand.lookup(command: nil, payload: payload, in: directory, noting: log, digested: digested, couldAnswer: { _, _ in declared }, allowed: { ledger.rerunsAllowed(session: advice.key, among: $0) }) else {
                return letThrough()
            }
            let verdict = PreToolUseCommand.outcome(
                to: lookup,
                session: session,
                context: advice,
                payload: payload,
                cwd: directory,
                ledger: ledger,
                usage: usageLog,
                suppressions: log,
                answerer: { InPlaceAnswerer.answer($0, serverGone: $1, timeBudget: $2, backoff: backoff) },
                couldAnswer: { _, _ in declared }
            ).verdict
            return verdict.rule == "noLookup" ? letThrough() : verdict.line
        }
        return (line, context.logged.compactMap { $0["rule"] as? String })
    }
}

extension ShellWindowFoldHookTests {
    /// The scratch state one context's calls share: its ledger, usage log and suppression log, and a session no real log holds.
    private struct Context {
        let ledger: AdviceLedger
        let usage: URL
        let suppressions: URL
        let session = "fold-\(UUID().uuidString)"

        init() throws {
            ledger = try AdviceLedger(directory: TemporaryDirectory.make("advice"))
            usage = try TemporaryDirectory.make("usage").appendingPathComponent("usage.jsonl")
            suppressions = try TemporaryDirectory.make("suppressions").appendingPathComponent("suppressions.jsonl")
        }

        /// The suppression log's entries, in order.
        var logged: [[String: Any]] {
            let text = (try? String(contentsOf: suppressions, encoding: .utf8)) ?? ""
            return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        }
    }

    /// A decision carried off the thread it was made on.
    private struct Decided: Sendable {
        let json: String?
        let token: String
        let call: String?
        let rule: String?
        let reason: String?
    }
}
