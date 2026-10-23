//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A page cut that lands where no closing line can state its own size is cut one member line shorter, never left to end the read as `overSize`.
///
/// A refusal whose closing line comes to the budget's edge on its first draft has no length that states its own size: its served figure prints `10.0 kB` below ten thousand bytes and `10 kB` from there, two bytes apart.
@Suite(.temporaryDirectories)
struct PageCutSizeFixedPointTests {
    private static var path: String {
        "Sources/App/Crate.swift"
    }

    private static var standsIn: String {
        "this digest did not weigh itself against the file's source"
    }

    /// A `Crate` of seventy members whose digest is over the size budget, led by a member whose name is `lead` and `extra` more letters, which moves every page's bytes by `extra`.
    private static func write(extra: Int, in root: URL) async throws {
        let summary = "Takes crate number %d out of the stack and weighs it against the others the depot is holding for the harbour."
        let pad = " //" + String(repeating: "x", count: 157)
        let lead = "    /// Leads.\n    func lead\(String(repeating: "y", count: extra))() -> Int { 0 }"
        let members = (1 ... 70).map { index in
            "    /// \(summary.replacingOccurrences(of: "%d", with: "\(index)"))\n    func take\(index)(first: Int, second: String, third: [Int], fourth: Double) -> Int {\n        let count = \(index)\(pad)\n        return count * 2\n    }"
        }
        try ("/// A crate.\nstruct Crate {\n" + ([lead] + members).joined(separator: "\n") + "\n}\n")
            .write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        try await SiftEngine(directory: root).ensureFresh()
    }

    /// The bytes the refusal carrying the first page of `size` member lines is served in, and whether it states its own size.
    private static func page(_ size: Int, in root: URL, sourceLocation: SourceLocation = #_sourceLocation) async throws -> InPlaceAnswer.Refusal {
        let engine = try SiftEngine(directory: root)
        let freshness = try await engine.ensureFresh()
        let paged = try #require(try FileDigestParts.wholeFileDigest(path, in: root.path, engine: engine, spelling: .toolCall, pageSize: size, checkingReach: false), sourceLocation: sourceLocation)
        let computed = try InPlaceAnswerer.Computed(calls: [paged.call], root: root.path, answer: engine.framing(freshness).syntacticHeaderLine + "\n" + paged.text, standsIn: standsIn)
        let conditions = try InPlaceAnswerer.Conditions(directory: root.path, serverGone: false, wholeCommand: true, lookups: 1, sizeBudget: InPlaceAnswer.sizeBudget, backoff: InPlaceAnswerTests.backoff(), oversized: nil)
        return InPlaceAnswerer.framed(computed, note: nil, under: conditions).1
    }

    /// The largest page size whose refusal, as first drafted, is inside the size budget.
    private static func largestDraftFitting(in root: URL) async throws -> Int {
        var size = 1
        while try await page(size + 1, in: root).served <= InPlaceAnswer.sizeBudget {
            size += 1
        }
        return size
    }

    /// Across the flip of the served figure from `10.0 kB` to `10 kB`, exactly two framings, a byte apart, have no closing line stating its own size, and their drafts come to the budget's edge: every other framing has one.
    @Test
    func twoFramingsAtTheFlipHaveNoSelfConsistentSize() {
        var unstated: [(padding: Int, served: Int)] = []
        for padding in 9800 ... 10100 {
            let refusal = InPlaceAnswer.reason(calls: ["digest Gizmo.swift"], answer: String(repeating: "x", count: padding), source: 608_000, standsIn: Self.standsIn)
            if !refusal.statesItsSize {
                unstated.append((padding, refusal.served))
            } else {
                #expect(refusal.text.hasSuffix("\(ByteSize.short(refusal.served)) served (98% smaller)."), "\(refusal.text.suffix(60))")
            }
        }

        #expect(unstated.count == 2 && unstated[1].padding == unstated[0].padding + 1, "\(unstated)")
        #expect(unstated.allSatisfy { (9999 ... 10001).contains($0.served) }, "\(unstated)")
    }

    /// A whole read whose largest page, as drafted, lands where no closing line states its size is answered with the page one member line shorter, inside the budget and stating its size, not run as `overSize`.
    @Test
    func aPageWhoseSizeHasNoFixedPointIsCutOneLineShorter() async throws {
        let root = try await InPlaceAnswerTests.indexedRepository()
        try await Self.write(extra: 0, in: root)
        let size = try await Self.largestDraftFitting(in: root)
        let drafted = try await Self.page(size, in: root).served
        // Moved one byte short of the budget, the page lands on the first framing at the flip.
        let shift = InPlaceAnswer.sizeBudget - 1 - drafted
        try #require(shift >= 0)
        try await Self.write(extra: shift, in: root)
        // The page the drafts would keep lands in the flip and cannot state its size; the next is over the budget.
        let stuck = try await Self.page(size, in: root)
        try #require(!stuck.statesItsSize && stuck.served <= InPlaceAnswer.sizeBudget, "\(stuck.served) \(stuck.statesItsSize)")
        try #require(try await Self.page(size + 1, in: root).served > InPlaceAnswer.sizeBudget)

        let match = try #require(InPlaceShape.match(forShell: "cat \(Self.path)", in: root.path))
        let backoff = try InPlaceAnswerTests.backoff()
        let outcome = await InPlaceAnswerTests.onItsOwnThread {
            InPlaceAnswerer.answer(match, serverGone: false, timeBudget: InPlaceAnswerTests.roomy, sizeBudget: InPlaceAnswer.sizeBudget, backoff: backoff)
        }

        guard case let .answered(answered) = outcome else {
            Issue.record("expected the page one member line shorter, got \(outcome)")
            return
        }
        let served = answered.reason.utf8.count

        #expect(served <= InPlaceAnswer.sizeBudget)
        #expect(answered.reason.contains("→ \(ByteSize.short(served)) served ("), "\(answered.reason.suffix(80))")
        #expect(answered.reason.contains("pass offset: \(size - 1)"), "\(answered.reason.suffix(300))")
    }
}
