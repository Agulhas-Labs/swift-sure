//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// What the scan prices as a saving: only a read the hook intercepted, summed on both sides, with every other call counted beside it and never folded in.
@Suite(.temporaryDirectories)
struct UsageScanPricingTests {
    // MARK: Fixtures

    private static func writeLog(_ lines: [String]) throws -> URL {
        let file = try TemporaryDirectory.make("usage-pricing").appendingPathComponent("usage.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func entry(
        tool: String,
        target: String,
        timestamp: String = "2026-07-30T10:00:00Z",
        bytes: (out: Int, source: Int)? = nil,
        served: Int? = nil,
        via: String? = nil,
        intercepted: String? = nil
    ) -> String {
        var object: [String: Any] = ["tool": tool, "target": target, "root": "/repo/a", "ms": 10, "ok": true, "ts": timestamp]
        object["via"] = via
        object["intercepted"] = intercepted
        if let bytes {
            object["outBytes"] = bytes.out
            object["srcBytes"] = bytes.source
        }
        // The half a line carries when the answer had no denominator to weigh itself against.
        if let served {
            object["outBytes"] = served
        }
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    /// An intercepted window, the way the advice hook logs one: the bytes the command named, the bytes served.
    private static func window(_ target: String, out: Int, source: Int, timestamp: String = "2026-07-30T10:00:00Z") -> String {
        entry(tool: "digest", target: target, timestamp: timestamp, bytes: (out: out, source: source), via: "hook", intercepted: "window")
    }

    private static func scan(_ lines: [String]) throws -> UsageScan {
        try UsageScan.load(fileURL: writeLog(lines)).get()
    }

    // MARK: Pricing

    /// Savings are summed on both sides, not averaged per call.
    ///
    /// A mean of per-call ratios would read 30% here, letting the tiny answer outweigh the large one. The digest made by choice is counted beside them, unpriced.
    @Test
    func savingsSumBothSidesAndStateWhatTheyWerePricedOn() throws {
        let scan = try Self.scan([
            Self.window("Small", out: 10, source: 20),
            Self.window("Big", out: 100, source: 1000),
            Self.entry(tool: "digest", target: "Voluntary", bytes: (out: 50, source: 5000)),
            Self.entry(tool: "where", target: "Big"),
        ])
        let savings = try #require(scan.savings)

        #expect(savings.total.calls == 2)
        #expect(savings.total.served == 110)
        #expect(savings.total.source == 1020)
        #expect(savings.total.saved == 910)
        #expect(savings.unpriced?.calls == 2)
        #expect(savings.headline.contains("~227 tokens saved on 2 intercepted reads (file or window asked for − answer served); 2 other calls unpriced"))
        #expect(!savings.headline.contains("leans high"))
    }

    /// Three generations of log line coexist, and none but an intercepted read is priced.
    @Test
    func onlyAnInterceptedReadIsPricedWhateverElseRecordedItsBytes() throws {
        let scan = try Self.scan([
            Self.entry(tool: "digest", target: "Ancient", timestamp: "2026-08-01T09:00:00Z"),
            Self.entry(tool: "digest", target: "Voluntary", timestamp: "2026-08-18T09:00:00Z", bytes: (out: 100, source: 1000)),
            Self.entry(tool: "where", target: "Looked up", timestamp: "2026-08-27T09:00:00Z", served: 4000),
            Self.window("Asked", out: 100, source: 1000, timestamp: "2026-08-28T09:00:00Z"),
        ])
        let savings = try #require(scan.savings)

        #expect(scan.entries.count == 4)
        #expect(scan.entries.map { $0.answer?.served } == [nil, 100, 4000, 100])
        #expect(scan.entries.compactMap(\.credited).count == 1)
        #expect(savings.total.calls == 1)
        #expect(savings.total.served == 100)
        #expect(savings.total.saved == 900)
        #expect(savings.unpriced?.calls == 3)
        #expect(savings.unpriced?.served == 4100)
    }

    /// The unpriced note says what the calls served and why they carry no saving.
    @Test
    func theUnpricedCallsSayWhatTheyServedAndWhyTheyAreNotPriced() throws {
        let scan = try Self.scan([
            Self.window("Measured", out: 100, source: 1000, timestamp: "2026-08-18T09:00:00Z"),
            Self.entry(tool: "where", target: "Before", timestamp: "2026-08-20T09:00:00Z"),
            Self.entry(tool: "where", target: "After", timestamp: "2026-08-27T09:00:00Z", served: 4000),
        ])
        let unpriced = try #require(scan.savings?.unpriced)

        #expect(unpriced.calls == 2)
        #expect(unpriced.recorded == 1)
        #expect(unpriced.note.contains("1 of them served 4.0 kB"))
        #expect(unpriced.note.contains("nothing observed to price them against"))
    }

    /// A hook answer logged before the log recorded what it intercepted is unpriced, and the note names it.
    @Test
    func aHookAnswerWithoutTheInterceptedFieldIsUnpricedAndSaysSo() throws {
        let scan = try Self.scan([
            Self.window("Asked", out: 100, source: 1000),
            Self.entry(tool: "digest", target: "Old", bytes: (out: 100, source: 1000), via: "hook"),
        ])
        let unpriced = try #require(scan.savings?.unpriced)

        #expect(unpriced.calls == 1)
        #expect(unpriced.unlabelled == 1)
        #expect(unpriced.note.hasSuffix("1 of them hook answers logged before the field that prices one"))
    }

    /// A log of voluntary calls, and lines written before the byte fields existed, state no saving at all.
    @Test
    func aLogOfVoluntaryCallsStatesNoSaving() throws {
        let voluntary = try Self.scan([
            Self.entry(tool: "digest", target: "Sources/App/Depot.swift", bytes: (out: 800, source: 9000)),
            Self.entry(tool: "where", target: "Depot"),
        ])
        let ancient = try Self.scan([
            Self.entry(tool: "digest", target: "Widget"),
            Self.entry(tool: "where", target: "Widget"),
        ])

        #expect(voluntary.savings == nil)
        #expect(ancient.savings == nil)
    }

    /// With every priced call on one side there is no split to print twice, and with every call priced there is no unpriced count.
    @Test
    func aWindowOfOnlyPricedCallsHasNoSplitAndNoUnpricedCount() throws {
        let savings = try #require(Self.scan([
            Self.window("Big", out: 100, source: 1000),
            Self.window("Bigger", out: 200, source: 4000),
        ]).savings)

        #expect(savings.split.isEmpty)
        #expect(savings.unpriced == nil)
        #expect(!savings.headline.contains("unpriced"))
        #expect(savings.total.calls == 2)
    }
}
