//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the skips the answer lists when the event stream is read beside the console: one entry per skipped test, however the two sources overlap.
struct RunStreamedSkipListingTests {
    private static func streamID(_ listed: String) -> String {
        "\(listed)/T.swift:3:6".replacingOccurrences(of: "/", with: #"\/"#)
    }

    /// A stream declaring a test named `same()` in each of `suites` and skipping it.
    private static func skippingStream(_ suites: [String]) -> ShardEventStream {
        ShardEventStream.read(suites.flatMap { suite -> [String] in
            let id = streamID("LibTests.\(suite)/same()")
            return [
                #"{"kind":"test","payload":{"id":"\#(id)","isParameterized":false,"kind":"function","name":"same()"},"version":"6.4.0"}"#,
                #"{"kind":"event","payload":{"instant":{"absolute":1,"since1970":0},"iteration":1,"kind":"testSkipped","messages":[],"testID":"\#(id)"},"version":"6.4.0"}"#,
            ]
        }.joined(separator: "\n"))
    }

    private static func outcomes(console: [String], stream: ShardEventStream) -> RunTestOutcomes {
        var filter = RunOutputFilter(invokedAs: ["swift", "test"])
        filter.consume(Data((console.joined(separator: "\n") + "\n").utf8))
        filter.read(eventStream: stream)
        return filter.finish(exitCode: 0).testOutcomes
    }

    /// Two suites' tests of one name are skipped in the stream and the console relays one: the stream carries the other, so the answer's two skips are two listed entries.
    @Test
    func twoSkipsOfOneNameWhereTheConsoleRelayedOneAreListedTwice() {
        let console = ["◇ Test run started.", "➜ Test same() skipped.", "✔ Test run with 2 tests in 2 suites passed after 0.001 seconds."]

        let outcomes = Self.outcomes(console: console, stream: Self.skippingStream(["AlphaTests", "BetaTests"]))

        #expect(outcomes["same()"]?.skipped == 2)
        #expect(outcomes.skips.map(\.name) == ["same()", "same()"])
    }

    /// One test skipped, reported by both the console and the stream: the fold passes on nothing beyond the console's count, so it is listed once.
    @Test
    func aSkipTheConsoleAndTheStreamBothReportForOneTestIsListedOnce() {
        let console = ["◇ Test run started.", "➜ Test same() skipped.", "✔ Test run with 1 test in 1 suite passed after 0.001 seconds."]

        let outcomes = Self.outcomes(console: console, stream: Self.skippingStream(["AlphaTests"]))

        #expect(outcomes["same()"]?.skipped == 1)
        #expect(outcomes.skips.map(\.name) == ["same()"])
    }
}
