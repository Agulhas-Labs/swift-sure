//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// A `Read` window whose members answer would list members of one top-level declaration only runs, as a window inside one member does; a shell window there, and a `Read` window across two top-level declarations, are still answered with their members.
@Suite(.temporaryDirectories)
struct InPlaceWindowOneDeclarationTests {
    /// `source` written to `Sources/App/<name>` in a fresh indexed repository, every one of `widened` (1-based) padded with a trailing comment wide enough that the window's own source outweighs its members answer by more than ``InPlaceAnswer/windowSavingFloor``.
    private static func repository(_ name: String, source: String, widened: ClosedRange<Int>) async throws -> URL {
        let root = try await InPlaceAnswerTests.indexedRepository()
        let file = root.appendingPathComponent("Sources/App/\(name)")
        var rows = source.components(separatedBy: "\n")
        let filler = String(repeating: "x", count: 600)
        for line in widened where rows.indices.contains(line - 1) {
            rows[line - 1] += " // \(filler)"
        }
        try rows.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        try await SiftEngine(directory: root).ensureFresh()
        return root
    }

    /// Two structs, `Alpha` on lines 2-12 with members `a1()` (3-9), `a2()` and `a3()`, and `Beta` on lines 14-22, its lines 4-20 padded.
    private static func twoDeclarations() async throws -> URL {
        let source = """
        /// Two.
        struct Alpha {
            func a1() -> Int {
                let x1 = 1
                let x2 = 2
                let x3 = 3
                let x4 = 4
                return x1 + x2 + x3 + x4
            }
            func a2() -> Int { 2 }
            func a3() -> Int { 3 }
        }

        struct Beta {
            func b1() -> Int { 1 }
            func b2() -> Int {
                let y1 = 1
                let y2 = 2
                let y3 = 3
                return y1 + y2 + y3
            }
        }

        """
        return try await repository("Two.swift", source: source, widened: 4 ... 20)
    }

    /// The outcome for `match`, on a thread of its own as the hook runs it.
    private static func outcome(_ match: InPlaceShape.Match) async throws -> InPlaceAnswerer.Outcome {
        let backoff = try InPlaceAnswerTests.backoff()
        return await InPlaceAnswerTests.onItsOwnThread {
            InPlaceAnswerer.answer(match, timeBudget: InPlaceAnswerTests.roomy, sizeBudget: InPlaceAnswer.sizeBudget, backoff: backoff)
        }
    }

    /// The targets `outcome` answers with, or a recorded issue.
    private static func answeredTargets(_ outcome: InPlaceAnswerer.Outcome, sourceLocation: SourceLocation = #_sourceLocation) -> [String] {
        guard case let .answered(answered) = outcome else {
            Issue.record("expected an answer, got \(outcome)", sourceLocation: sourceLocation)
            return []
        }
        return answered.calls.map(\.target)
    }

    /// A `Read` across several members of one type runs: its members answer would list that type's header and those members' lines, and the source of the same lines followed nine such answers in ten.
    @Test
    func aReadAcrossSeveralMembersOfOneTypeRuns() async throws {
        let root = try await Self.twoDeclarations()
        let match = try WindowReadSpelling.read.match(path: "Sources/App/Two.swift", lines: 4 ... 11, in: root)

        #expect(try await Self.outcome(match) == .withheld(.linesNotShown))
    }

    /// The same lines asked for with `sed -n` keep the shell window's price, and are answered with the members they overlap.
    @Test
    func theSameWindowAsSedIsAnsweredWithItsMembers() async throws {
        let root = try await Self.twoDeclarations()
        let match = try WindowReadSpelling.shell.match(path: "Sources/App/Two.swift", lines: 4 ... 11, in: root)

        let outcome = try await Self.outcome(match)

        #expect(Self.answeredTargets(outcome) == ["Sources/App/Two.swift:4-11"])
        guard case let .answered(answered) = outcome else { return }
        #expect(answered.reason.contains("Sources/App/Two.swift lines 4-11 overlap:\nstruct Alpha"))
        #expect(answered.reason.contains("func a3() -> Int"))
    }

    /// A `Read` across members of two top-level declarations is still answered with them.
    @Test
    func aReadAcrossTwoTopLevelDeclarationsIsAnswered() async throws {
        let root = try await Self.twoDeclarations()
        let match = try WindowReadSpelling.read.match(path: "Sources/App/Two.swift", lines: 10 ... 17, in: root)

        let outcome = try await Self.outcome(match)

        #expect(Self.answeredTargets(outcome) == ["Sources/App/Two.swift:10-17"])
        guard case let .answered(answered) = outcome else { return }
        #expect(answered.reason.contains("struct Alpha"))
        #expect(answered.reason.contains("struct Beta"))
    }

    /// A `Read` inside one extension printing most of the file is weighed as its whole read, as the same lines through `sed -n` are, rather than run for lying in one declaration.
    @Test
    func aReadPrintingMostOfTheFileIsWeighedAsItsWholeRead() async throws {
        let source = """
        extension String {
            func e1() -> Int {
                let z1 = 1
                let z2 = 2
                let z3 = 3
                return z1 + z2 + z3
            }
            func e2() -> Int { 2 }
            func e3() -> Int { 3 }
            func e4() -> Int { 4 }
        }

        """
        let root = try await Self.repository("Most.swift", source: source, widened: 2 ... 10)
        let read = try WindowReadSpelling.read.match(path: "Sources/App/Most.swift", lines: 2 ... 11, in: root)
        let shell = try WindowReadSpelling.shell.match(path: "Sources/App/Most.swift", lines: 2 ... 11, in: root)

        let outcome = try await Self.outcome(read)
        let shellOutcome = try await Self.outcome(shell)

        #expect(Self.answeredTargets(outcome) == ["Sources/App/Most.swift:2-11"])
        guard case let .answered(answered) = outcome, case let .answered(answeredShell) = shellOutcome else {
            Issue.record("expected both spellings answered, got \(outcome) and \(shellOutcome)")
            return
        }
        #expect(answered.wholeRead != nil, "weighed as the whole read of the file")
        #expect(answered.wholeRead == answeredShell.wholeRead)
        #expect(answered.reason == answeredShell.reason)
    }
}
