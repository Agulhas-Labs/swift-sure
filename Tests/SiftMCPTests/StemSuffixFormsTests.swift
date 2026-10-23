//
// Copyright © Agulhas Labs
//

@testable import SiftMCP
import Testing

/// The reader of an answered refusal's opening line takes the stem only where what follows it is a suffix the writer produces, so a failed command whose output quotes an answer is not read as one.
struct StemSuffixFormsTests {
    private static let calls = ["digest Sources/App/Depot.swift"]

    /// Every form the writer produces, with and without a note and the teed clause, reads back as its calls and note.
    @Test(arguments: [
        (rerun: (lines: Int, bytes: Int)?.none, teed: [String]()),
        (rerun: .none, teed: ["out.txt"]),
        (rerun: .none, teed: ["a.txt", "b.txt"]),
        (rerun: .some((203, 12400)), teed: []),
        (rerun: .some((9, 300)), teed: ["out.txt"]),
        (rerun: .some((9, 300)), teed: ["a.txt", "b.txt"]),
    ])
    func everyFormTheWriterProducesParses(rerun: (lines: Int, bytes: Int)?, teed: [String]) {
        let plain = InPlaceAnswer.openingLine(calls: Self.calls, rerun: rerun, teed: teed)
        let noted = InPlaceAnswer.openingLine(calls: Self.calls, note: "only lines 1-5 are shown", rerun: rerun, teed: teed)

        #expect(InPlaceAnswer.calls(inOpeningLine: plain) == Self.calls, "\(plain)")
        #expect(InPlaceAnswer.note(inOpeningLine: plain) == nil, "\(plain)")
        #expect(InPlaceAnswer.calls(inOpeningLine: noted) == Self.calls, "\(noted)")
        #expect(InPlaceAnswer.note(inOpeningLine: noted) == "only lines 1-5 are shown", "\(noted)")
    }

    /// A line that quotes the stem and goes on with other text, as a grep hit on a test literal does, is not an answer.
    @Test(arguments: [
        "Tests/X.swift:12: \"swift-sure answered this with `digest A.swift` instead of running it — re-run the identical command if you wanted its raw output.\" ++ more",
        "Tests/X.swift:12: swift-sure answered this with `digest A.swift` instead of running it — re-run the identical command\" ++ more",
        "Tests/X.swift:12: `digest A.swift` instead of running it — re-run the identical command for all 3 lines, about 9 tokens, or Read more.",
        "swift-sure answered this with `digest A.swift` instead of running it — re-run the identical command if you wanted its raw output. And more.",
        "swift-sure answered this with `digest A.swift` instead of running it — re-run the identical command for all x lines, about 9 tokens, or Read just a member's line range below with offset and limit.",
        "swift-sure answered this with `digest A.swift` instead of running it — re-run the identical command if you wanted its raw output (not run: out.txt was kept).",
    ])
    func aStemQuotedMidLineIsNotAnAnswer(line: String) {
        #expect(InPlaceAnswer.calls(inOpeningLine: line) == nil)
        #expect(InPlaceAnswer.note(inOpeningLine: line) == nil)
    }
}
