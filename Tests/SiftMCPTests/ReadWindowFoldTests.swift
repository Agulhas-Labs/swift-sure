//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// The hook judges a ranged `Read` of a Swift file nothing has located as the shell window `cat -n F | sed -n a,bp`: answered with those lines, comment runs folded, or, where the fold lets it through, given the reading it had before the fold.
@Suite(.temporaryDirectories)
struct ReadWindowFoldTests {
    /// The commented file's path in the repository.
    static var commented: String {
        "Sources/App/Commented.swift"
    }

    /// The code-only file's path in the repository.
    static var plain: String {
        "Sources/App/Plain.swift"
    }

    /// A repository holding `Commented.swift`, fifty members under three doc-comment lines each, the same file again under a name with a space in it, and `Plain.swift`, two hundred lines of code and no comment.
    private static func repository() throws -> URL {
        let root = try MCPTestRepo.make(declaring: "Alpha")
        let members = (1 ... 50).map { index in
            "    /// Member \(index) explains what it counts, in words.\n    /// It says so at length, so its comment outweighs its code.\n    /// And a third line closes the run.\n    func stock\(index)() -> Int { \(index) }"
        }
        let commentedText = "struct Commented {\n" + members.joined(separator: "\n") + "\n}\n"
        try commentedText.write(to: root.appendingPathComponent(commented), atomically: true, encoding: .utf8)
        try commentedText.replacingOccurrences(of: "struct Commented", with: "struct Spaced").write(to: root.appendingPathComponent("Sources/App/Spaced Out.swift"), atomically: true, encoding: .utf8)
        let lines = (1 ... 198).map { "    let value\($0) = \($0)" }
        try ("struct Plain {\n" + lines.joined(separator: "\n") + "\n}\n")
            .write(to: root.appendingPathComponent(plain), atomically: true, encoding: .utf8)
        return root
    }

    /// An unlocated `Read` window over a commented range is answered with its lines, numbered from its `offset` as `cat -n` numbers them, comment runs folded, and says the identical `Read` re-run prints them.
    @Test
    func anUnlocatedReadWindowIsAnsweredWithItsCommentsFolded() async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(Self.read(Self.commented, in: root, offset: 40, limit: 81), in: root, context: context)

        #expect(decided.verdict.line == "in-place\twindow \(Self.commented):40-120\tcommentsFolded")
        let reason = try #require(decided.verdict.reason)
        #expect(reason.hasPrefix("swift-sure answered `window \(Self.commented):40-120` instead of running it: "), "\(reason.prefix(200))")
        #expect(reason.contains(" folded; the identical Read re-run prints them. "), "\(reason.prefix(300))")
        #expect(!reason.contains("the identical command re-run"))
        #expect(reason.contains("\n    41\t    func stock10() -> Int { 10 }\n"), "\(reason.prefix(600))")
        #expect(reason.contains(": // … 3 comment lines\n"))
        #expect(!reason.contains("    39\t"))
        #expect(!reason.contains("   121\t"))
        #expect(decided.json?.contains("deny") == true)
    }

    /// A `Read` naming a file with a space in its path is read as that one file.
    @Test
    func aReadOfAPathWithASpaceIsFolded() async throws {
        let root = try Self.repository()
        let context = try Context()

        let decided = try await Self.decide(Self.read("Sources/App/Spaced Out.swift", in: root, offset: 1, limit: 120), in: root, context: context)

        #expect(decided.verdict.line == "in-place\twindow Sources/App/Spaced Out.swift:1-120\tcommentsFolded")
    }

    /// The identical `Read` re-run after a fold is allowed by the ledger.
    @Test
    func theIdenticalReadReRunAfterAFoldIsAllowed() async throws {
        let root = try Self.repository()
        let context = try Context()
        let input = Self.read(Self.commented, in: root, offset: 1, limit: 120)

        #expect(try await Self.decide(input, in: root, context: context).verdict.rule == "commentsFolded")
        #expect(try await Self.decide(input, in: root, context: context).verdict.line == "allowed\t\tledger")
    }

    /// A code-only `Read` window, which the fold lets through, gets the verdict it had before the fold.
    @Test
    func aCodeOnlyReadWindowKeepsTheReadingItHadBeforeTheFold() async throws {
        let root = try Self.repository()
        let input = Self.read(Self.plain, in: root, offset: 1, limit: 100)

        let live = try await Self.decide(input, in: root, context: Context())
        let before = try await Self.judged(input, in: root, context: Context(), folding: false)

        #expect(live.verdict.rule != "commentsFolded")
        #expect(live.verdict.line == before)
    }

    /// A `Read` window of a file the ledger or the usage log has located is let through as a located window always was, never folded.
    @Test
    func aLocatedFilesReadWindowIsNotFolded() async throws {
        let root = try Self.repository()
        let input = Self.read(Self.commented, in: root, offset: 1, limit: 120)
        let repository = try #require(CallerRoot.root(forCallerIn: root.path))
        let ledgerLocated = try Context()
        ledgerLocated.ledger.noteIndexCall(session: AdviceContext.resolve(sessionID: ledgerLocated.session, transcriptPath: nil).key, calls: ["digest \(Self.commented)"], digests: [repository: [Self.commented]])

        #expect(try await Self.decide(input, in: root, context: ledgerLocated).verdict.line == "allowed\t\tlocatedWindow")
        #expect(try await Self.judged(input, in: root, context: Context(), usageLocated: [Self.commented]) == "allowed\t\tlocatedWindow")
    }

    /// A whole `Read`, or a `Read` window reaching every line of its file, goes the way a whole read always did.
    @Test(arguments: [nil, 1] as [Int?])
    func aWholeReadIsUnchanged(offset: Int?) async throws {
        let root = try Self.repository()
        let input = offset.map { Self.read(Self.commented, in: root, offset: $0, limit: 2000) } ?? ["file_path": root.appendingPathComponent(Self.commented).path]

        let live = try await Self.decide(input, in: root, context: Context())
        let before = try await Self.judged(input, in: root, context: Context(), folding: false)

        #expect(live.verdict.rule != "commentsFolded")
        #expect(live.verdict.line == before)
    }

    /// The shell line a ranged `Read` stands for: `cat -n` of its file, relative to the directory it is read from where it lies under it, quoted where it must be, through `sed -n` of its lines.
    @Test
    func aReadWindowStandsForANumberedSedWindow() {
        let read = { (input: [String: Any], directory: String?) in ShellWindowHook.readWindowShell(payload: ["tool_name": "Read", "tool_input": input], in: directory) }

        #expect(read(["file_path": "/repo/Sources/A.swift", "offset": 40, "limit": 241], "/repo") == "cat -n Sources/A.swift | sed -n 40,280p")
        #expect(read(["file_path": "/repo/Sources/A.swift", "limit": 50], "/repo") == "cat -n Sources/A.swift | sed -n 1,50p")
        #expect(read(["file_path": "/repo/Sources/A.swift", "offset": 0, "limit": 10], "/repo") == "cat -n Sources/A.swift | sed -n 1,10p")
        #expect(read(["file_path": "/repo/Sources/A.swift", "offset": 7], "/repo") == "cat -n Sources/A.swift | sed -n 7,2006p")
        #expect(read(["file_path": "/other/A.swift", "offset": 1, "limit": 5], "/repo") == "cat -n /other/A.swift | sed -n 1,5p")
        #expect(read(["file_path": "/repo/It's here.swift", "offset": 1, "limit": 5], "/repo") == "cat -n 'It'\\''s here.swift' | sed -n 1,5p")
        #expect(read(["file_path": "/repo/Sources/A.swift"], "/repo") == nil)
        #expect(read(["file_path": "/repo/README.md", "offset": 1, "limit": 5], "/repo") == nil)
        #expect(ShellWindowHook.readWindowShell(payload: ["tool_name": "Bash", "tool_input": ["command": "sed -n 1,5p A.swift"]], in: "/repo") == nil)
    }

    /// A later window of a file the fold answered is weighed again, while the identical re-run of the first stays allowed.
    @Test
    func aLaterWindowAfterAFoldIsNotAllowedByTheLedger() async throws {
        let root = try Self.repository()
        let context = try Context()
        let first = Self.read(Self.commented, in: root, offset: 1, limit: 60)
        let later = Self.read(Self.commented, in: root, offset: 61, limit: 60)

        #expect(try await Self.decide(first, in: root, context: context).verdict.rule == "commentsFolded")
        let second = try await Self.decide(later, in: root, context: context)
        #expect(second.verdict.line != "allowed\t\tledger", "\(second.verdict.line)")
        #expect(second.verdict.rule == "commentsFolded")
        #expect(try await Self.decide(first, in: root, context: context).verdict.line == "allowed\t\tledger")
    }

    /// A `limit` that overflows the window's last line is no crash: the window reads to the end of the file.
    @Test
    func aLimitPastTheIntegerRangeReadsToTheEndOfTheFile() async throws {
        let root = try Self.repository()
        let input = Self.read(Self.commented, in: root, offset: 100, limit: Int.max)

        let decided = try await Self.decide(input, in: root, context: Context())

        #expect(decided.verdict.line == "in-place\twindow \(Self.commented):100-202\tcommentsFolded")
    }

    /// A `Read` the fold lets through writes the one suppression row its reading before the fold noted.
    @Test
    func aReadTheFoldLetsThroughWritesOneSuppressionRow() async throws {
        let root = try Self.repository()
        let context = try Context()

        _ = try await Self.decide(Self.read(Self.plain, in: root, offset: 1, limit: 100), in: root, context: context)

        let rows = ((try? String(contentsOf: context.suppressions, encoding: .utf8)) ?? "").split(separator: "\n")

        #expect(rows.count == 1, "\(rows)")
    }

    /// A `Read` input for the file at `relative` in `root`, through `limit` lines from `offset`.
    private static func read(_ relative: String, in root: URL, offset: Int, limit: Int) -> [String: Any] {
        ["file_path": root.appendingPathComponent(relative).path, "offset": offset, "limit": limit]
    }

    /// The hook's decision on a `Read` with `input`, run from `root` in `context`, as the live hook makes it.
    private static func decide(_ input: [String: Any], in root: URL, context: Context) async throws -> (json: String?, verdict: PreToolUseCommand.Verdict) {
        let backoff = try InPlaceAnswerTests.backoff()
        let payloadData = try JSONSerialization.data(withJSONObject: ["tool_name": "Read", "tool_input": input, "session_id": context.session, "tool_use_id": "toolu_read"])
        let (ledger, usage, suppressions, session, directory) = (context.ledger, UsageLog(fileURL: context.usage), context.suppressions, context.session, root.path)
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

    /// The hook's verdict line on a `Read` with `input` run from `root` in `context`, the lookup then its outcome, with `usageLocated` held by the usage log's whole digests and the fold on or, `folding` false, as the hook read the call before it.
    private static func judged(_ input: [String: Any], in root: URL, context: Context, usageLocated: [String] = [], folding: Bool = true) async throws -> String {
        let backoff = try InPlaceAnswerTests.backoff()
        let repository = CallerRoot.root(forCallerIn: root.path) ?? root.path
        let usage = try DigestedFilesTests.UsageLogFile(usageLocated.map { ["tool": "digest", "target": $0, "root": repository, "ms": 3, "ok": true, "session": context.session, "outBytes": 900, "srcBytes": 12000] })
        defer { usage.cleanup() }
        let payloadData = try JSONSerialization.data(withJSONObject: ["tool_name": "Read", "tool_input": input, "session_id": context.session, "tool_use_id": "toolu_read"])
        let digested = usage.digested
        let (ledger, usageLog, suppressions, session, directory) = (context.ledger, UsageLog(fileURL: context.usage), context.suppressions, context.session, root.path)
        return await InPlaceAnswerTests.onItsOwnThread { () -> String in
            let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]
            let advice = AdviceContext.resolve(sessionID: session, transcriptPath: nil)
            let noted = NotedRule()
            let log = SuppressionLog(fileURL: suppressions, noted: noted.record)
            let letThrough = { PreToolUseCommand.Verdict(token: "allowed", rule: noted.last ?? "noLookup").line }
            guard let lookup = PreToolUseCommand.lookup(command: nil, payload: payload, in: directory, noting: log, digested: digested, couldAnswer: { _, _ in true }, allowed: { ledger.rerunsAllowed(session: advice.key, among: $0) }, folding: folding) else {
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
                couldAnswer: { _, _ in true }
            ).verdict
            return verdict.rule == "noLookup" ? letThrough() : verdict.line
        }
    }
}

extension ReadWindowFoldTests {
    /// The scratch state one context's calls share: its ledger, usage log and suppression log, and a session no real log holds.
    private struct Context {
        let ledger: AdviceLedger
        let usage: URL
        let suppressions: URL
        let session = "read-fold-\(UUID().uuidString)"

        init() throws {
            ledger = try AdviceLedger(directory: TemporaryDirectory.make("advice"))
            usage = try TemporaryDirectory.make("usage").appendingPathComponent("usage.jsonl")
            suppressions = try TemporaryDirectory.make("suppressions").appendingPathComponent("suppressions.jsonl")
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
