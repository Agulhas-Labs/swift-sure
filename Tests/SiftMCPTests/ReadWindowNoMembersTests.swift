//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// A `Read` window is never answered with the members its lines overlap, where the same lines through `sed -n` are.
@Suite(.temporaryDirectories)
struct ReadWindowNoMembersTests {
    /// Two structs, `Alpha` on lines 2-12 and `Beta` on lines 14-22, their lines 4-20 padded wide enough that a window's own source outweighs its members answer.
    private static func repository() async throws -> URL {
        let root = try await InPlaceAnswerTests.indexedRepository()
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
        var rows = source.components(separatedBy: "\n")
        let filler = String(repeating: "x", count: 600)
        for line in 4 ... 20 where rows.indices.contains(line - 1) {
            rows[line - 1] += " // \(filler)"
        }
        let file = root.appendingPathComponent("Sources/App/Two.swift")
        try rows.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        try await SiftEngine(directory: root).ensureFresh()
        return root
    }

    /// The outcome for `match`, on a thread of its own as the hook runs it.
    private static func outcome(_ match: InPlaceShape.Match) async throws -> InPlaceAnswerer.Outcome {
        let backoff = try InPlaceAnswerTests.backoff()
        return await InPlaceAnswerTests.onItsOwnThread {
            InPlaceAnswerer.answer(match, timeBudget: InPlaceAnswerTests.roomy, sizeBudget: InPlaceAnswer.sizeBudget, backoff: backoff)
        }
    }

    /// A `Read` across members of two top-level types is not answered with those members: the whole digest saves under the floor, so the window runs.
    @Test
    func aReadAcrossTwoTypesIsNotAnsweredWithMembers() async throws {
        let root = try await Self.repository()
        let match = try WindowReadSpelling.read.match(path: "Sources/App/Two.swift", lines: 10 ... 17, in: root)

        let outcome = try await Self.outcome(match)

        #expect(outcome == .withheld(.linesNotShown))
    }

    /// The same lines through `sed -n` are still answered with the members they overlap.
    @Test
    func theSameWindowAsSedIsStillAnsweredWithMembers() async throws {
        let root = try await Self.repository()
        let match = try WindowReadSpelling.shell.match(path: "Sources/App/Two.swift", lines: 10 ... 17, in: root)

        let outcome = try await Self.outcome(match)

        guard case let .answered(answered) = outcome else {
            Issue.record("expected an answer, got \(outcome)")
            return
        }

        #expect(answered.calls.map(\.target) == ["Sources/App/Two.swift:10-17"])
        #expect(answered.reason.contains("struct Beta"))
    }
}
