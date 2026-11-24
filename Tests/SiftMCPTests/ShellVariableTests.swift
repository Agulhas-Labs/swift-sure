//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A variable a Bash line assigns itself is read as its value before the hook judges or records the line, and a word still holding an expansion is never recorded as a path.
@Suite(.temporaryDirectories)
struct ShellVariableTests {
    /// The hook's verdict for `command` as the payload carries it, decided by the real answerer against `root`.
    static func verdict(_ command: String, in root: URL) async throws -> PreToolUseCommand.Verdict {
        let backoff = try InPlaceAnswerTests.backoff()
        let advice = try TemporaryDirectory.make("advice")
        let usage = try TemporaryDirectory.make("usage").appendingPathComponent("usage.jsonl")
        let log = try TemporaryDirectory.make("suppressions").appendingPathComponent("suppressions.jsonl")
        return await InPlaceAnswerTests.onItsOwnThread { () -> PreToolUseCommand.Verdict in
            let payload: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": command], "session_id": "s1", "tool_use_id": "toolu_variable"]
            return PreToolUseCommand.decided(
                command: nil,
                payload: payload,
                cwd: root.path,
                session: "s1",
                context: AdviceContext.resolve(sessionID: "s1", transcriptPath: nil),
                answerer: { match, gone, _ in InPlaceAnswerer.answer(match, serverGone: gone, timeBudget: InPlaceAnswerTests.roomy, backoff: backoff) },
                ledger: AdviceLedger(directory: advice),
                usage: UsageLog(fileURL: usage),
                suppressions: log,
                couldAnswer: { _, _ in true }
            ).verdict
        }
    }

    /// The digests the advice ledger holds after the hook sees `command` run from `directory`.
    static func digests(_ command: String, from directory: URL) throws -> [String: Set<String>] {
        let ledger = try AdviceLedger(directory: TemporaryDirectory.make("advice"))
        let callers = try CallAttribution(directory: TemporaryDirectory.make("callers"))
        let context = AdviceContext.resolve(sessionID: "s1", transcriptPath: nil)
        _ = PreToolUseCommand.adviceTaken(
            session: "s1",
            context: context,
            payload: ["tool_name": "Bash", "tool_input": ["command": command]],
            cwd: directory.path,
            ledger: ledger,
            callers: callers
        )
        return ledger.digests(session: context.key)
    }

    // MARK: - Judged by its value

    /// The control: the literal line is answered in place, not plainly let through.
    @Test(arguments: ["F=Sources/App/Large.swift; cat $F", "F=\"Sources/App/Large.swift\"; cat \"${F}\""])
    func aBoundVariableIsJudgedAsTheLiteralPath(_ command: String) async throws {
        let root = try await CatSeveralFilesVerdictTests.repository()
        let literal = try await Self.verdict("cat Sources/App/Large.swift", in: root)

        let bound = try await Self.verdict(command, in: root)

        #expect(literal.token == "in-place", "\(literal)")
        #expect(bound.token == literal.token, "\(bound)")
        #expect(bound.rule == literal.rule, "\(bound)")
    }

    /// A value the text does not carry and a prefix assignment bind nothing: the line keeps the unbound use's verdict.
    @Test(arguments: [
        "F=$(ls Sources/App/Large.swift); cat $F", "F=Sources/App/Large.swift cat $F", "F=Sources/App/Large.swift & cat $F",
        "F=Sources/App/Large.swift; eval true; cat $F", "F='Sources/App/Large.swift '; cat $F",
    ])
    func aNonBindingAssignmentLeavesTheUseUnread(_ command: String) async throws {
        let root = try await CatSeveralFilesVerdictTests.repository()
        let unbound = try await Self.verdict("cat $F", in: root)

        let decided = try await Self.verdict(command, in: root)

        #expect(decided.token != "in-place", "\(decided)")
        #expect(decided.token == unbound.token, "\(decided)")
        #expect(decided.rule == unbound.rule, "\(decided)")
    }

    /// A binding never reaches a subshell or substitution that assigns the name again: the line is judged as it is without the binding.
    @Test(arguments: [
        ("F=Sources/App/Large.swift; (F=README.md; cat $F)", "(F=README.md; cat $F)"),
        ("F=Sources/App/Large.swift; echo \"$(F=README.md; cat $F)\"", "echo \"$(F=README.md; cat $F)\""),
    ])
    func aBindingDoesNotLeakIntoAReassigningSubshell(_ bound: String, _ alone: String) async throws {
        let root = try await CatSeveralFilesVerdictTests.repository()
        let unbound = try await Self.verdict(alone, in: root)

        let decided = try await Self.verdict(bound, in: root)

        #expect(decided.token != "in-place", "\(decided)")
        #expect(decided.token == unbound.token, "\(decided)")
        #expect(decided.rule == unbound.rule, "\(decided)")
    }

    // MARK: - Recorded by its value

    @Test
    func aDigestRootGivenThroughAVariableIsFiledUnderItsValue() throws {
        let root = try MCPTestRepo.make(declaring: "Gizmo")
        let sources = root.appendingPathComponent("Sources")
        let literal = try Self.digests("swift-sure digest --root \(root.path) Gizmo", from: sources)

        let bound = try Self.digests("R=\(root.path); swift-sure digest --root $R Gizmo", from: sources)

        #expect(!literal.isEmpty)
        #expect(bound == literal)
    }

    /// An unbound variable names no path, so the digest is filed nowhere rather than under the directory with the variable appended.
    @Test(arguments: ["swift-sure digest --root $R Gizmo", "swift-sure digest --root=${R} Gizmo", "swift-sure digest $T"])
    func anUnexpandedWordRecordsNothing(_ command: String) throws {
        let root = try MCPTestRepo.make(declaring: "Gizmo")

        let recorded = try Self.digests(command, from: root.appendingPathComponent("Sources"))

        #expect(recorded.isEmpty, "\(recorded)")
    }

    // MARK: - The expansion itself

    @Test(arguments: [
        ("F=a; cat $F ${F}x", "F=a; cat a ax"),
        ("F=\"a;b\"; cat $F", "F=\"a;b\"; cat 'a;b'"),
        ("F=x; echo '$F' \\$F \"'$F'\"", "F=x; echo '$F' \\$F \"'x'\""),
        ("F=x; cat $(echo $F) $F", "F=x; cat $(echo $F) x"),
        ("F=x; cat {a,b} $F", "F=x; cat {a,b} x"),
        ("F=x; unset F; cat $F", "F=x; unset F; cat $F"),
        ("F=x; F=$G; cat $F", "F=x; F=$G; cat $F"),
        ("F=x; export F=y; cat $F", "F=x; export F=y; cat $F"),
        ("true && F=x; cat $F", "true && F=x; cat $F"),
        ("(F=x; cat a); cat $F", "(F=x; cat a); cat $F"),
        ("F=x | cat; cat $F", "F=x | cat; cat $F"),
        ("cat $F; F=x", "cat $F; F=x"),
        ("F=*.swift; cat $F", "F=*.swift; cat $F"),
    ])
    func aLineIsExpandedAsTheShellWould(_ written: String, _ expanded: String) {
        #expect(ShellVariables.expanded(written) == expanded)
    }

    /// A use inside a subshell, group, substitution, function body or compound command is never replaced, and an assignment anywhere on the line unbinds the name from there on.
    @Test(arguments: [
        "F=x; echo \"$(cat '$F' $F)\"",
        "F=x; (cat $F)",
        "F=x; { cat $F; }",
        "F=x; cat `echo $F`",
        "F=x; f() { cat $F; }; f",
        "F=x; if true; then cat $F; fi",
        "F=x; for g in a; do cat $F; done",
        "F=x; (F=y); cat $F",
        "F=x; echo \"$(F=y)\"; cat $F",
        "F=x; f() { F=y; }; f; cat $F",
        "F=x; F[1]=y; cat $F",
        "F=x; F+=y; cat $F",
        "F=x; for F in y; do :; done; cat $F",
        "F=x; F=y cat $F",
    ])
    func aUseOffTheTopOrAfterAnotherAssignmentIsLeftAsWritten(_ written: String) {
        #expect(ShellVariables.expanded(written) == written)
    }

    /// A line holding anything that can assign a name without a plain assignment word binds nothing, and neither does a value holding a blank.
    @Test(arguments: [
        "F=x; eval G=y; cat $F",
        "F=x; source env.sh; cat $F",
        "F=x; . ./env.sh; cat $F",
        "F=x; printf -v F y; cat $F",
        "F=x; read F < a; cat $F",
        "F=x; declare G=y; cat $F",
        "F=x; local G; cat $F",
        "F=x; mapfile -t G < a; cat $F",
        "F=x; getopts ab G; cat $F",
        "F=x; let G=1; cat $F",
        "F=x; ((G = 1)); cat $F",
        "F=x; IFS=:; cat $F",
        "F=x; cat ${G:=y} $F",
        "F=x; $C G=y; cat $F",
        "F='a b'; cat \"$F\" $F",
        "F=\"a\tb\"; cat $F",
    ])
    func aLineThatCanAssignOtherwiseBindsNothing(_ written: String) {
        #expect(ShellVariables.expanded(written) == written)
    }

    /// The control for the line-wide rule: a `.` that is an argument, not a command, leaves the binding in place.
    @Test
    func aDotThatIsAnArgumentLeavesTheBinding() {
        #expect(ShellVariables.expanded("F=x; find . -name $F") == "F=x; find . -name x")
    }

    // MARK: - Emitted as written

    /// What the hook makes of `shell` run from Bash in permission mode `mode`, with no rule allowing the wrapping.
    static func emitted(_ shell: String, mode: String) throws -> (json: String?, verdict: PreToolUseCommand.Verdict) {
        let scratch = try TemporaryDirectory.make("emitted")
        let payload: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": shell, "description": "Run the tests"], "session_id": "s1", "permission_mode": mode]
        return PreToolUseCommand.decided(
            command: nil,
            payload: payload,
            cwd: "/repo",
            session: "s1",
            context: AdviceContext.resolve(sessionID: "s1", transcriptPath: nil),
            answerer: { _, _, _ in .withheld(.notExact) },
            ledger: AdviceLedger(directory: scratch.appendingPathComponent("advice")),
            usage: UsageLog(fileURL: scratch.appendingPathComponent("usage.jsonl")),
            suppressions: scratch.appendingPathComponent("suppressions.jsonl"),
            runPermission: { _ in WrappedRunPermission(allowed: [], vetoed: []) },
            couldAnswer: { _, _ in true }
        )
    }

    /// The hook's specific output decoded.
    static func specific(_ json: String?, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(#require(json, sourceLocation: sourceLocation).utf8)) as? [String: Any]
        return try #require(object?["hookSpecificOutput"] as? [String: Any], sourceLocation: sourceLocation)
    }

    /// The command the hook hands back is the user's line with only the wrapping applied, character for character, whatever it read the variables as.
    @Test(arguments: [
        ("D=build; (D=out; rm -rf $D); swift test", "D=build; (D=out; rm -rf $D); swift-sure run -- swift test"),
        ("D=build; rm -rf $D; swift test", "D=build; rm -rf $D; swift-sure run -- swift test"),
        ("D=build; swift build --scratch-path \"$D\"", "D=build; swift-sure run -- swift build --scratch-path \"$D\""),
    ])
    func aRewrittenBuildKeepsTheLineAsWritten(_ written: String, _ rewritten: String) throws {
        let outcome = try Self.emitted(written, mode: "bypassPermissions")

        let input = try #require(Self.specific(outcome.json)["updatedInput"] as? [String: Any])

        #expect(input["command"] as? String == rewritten)
        #expect(outcome.verdict.call == rewritten)
    }

    /// A refused build names its wrapping as the user wrote the line, not as the variables were read.
    @Test
    func aRefusedBuildNamesTheLineAsWritten() throws {
        let outcome = try Self.emitted("D=build; rm -rf $D; swift test", mode: "default")

        let reason = try #require(Self.specific(outcome.json)["permissionDecisionReason"] as? String)

        #expect(outcome.verdict.token == "deny")
        #expect(reason.contains("D=build; rm -rf $D; swift-sure run -- swift test"), "\(reason)")
        #expect(!reason.contains("rm -rf build"), "\(reason)")
    }

    /// An unquoted leading tilde in the value is the home directory, as the shell expands it when it assigns.
    @Test
    func aLeadingTildeIsExpandedWhereTheAssignmentLeavesItUnquoted() {
        let home = ("~/x" as NSString).expandingTildeInPath

        #expect(ShellVariables.expanded("F=~/x; cat \"$F\"") == "F=~/x; cat \"\(home)\"")
        #expect(ShellVariables.expanded("F='~/x'; cat $F") == "F='~/x'; cat '~/x'")
    }
}
