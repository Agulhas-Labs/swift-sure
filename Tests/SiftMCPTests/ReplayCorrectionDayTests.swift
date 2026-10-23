//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Covers the day `audit --replay` files a correction under in its per-day breakdown.
@Suite(.temporaryDirectories)
struct ReplayCorrectionDayTests {
    /// One transcript line at `stamp` (none when `nil`, as a line the harness wrote without a time), in assistant message `message` where given.
    private static func line(_ type: String, at stamp: String?, cwd: String?, block: [String: Any], message: String? = nil) -> Data {
        var content: [String: Any] = ["content": [block]]
        content["id"] = message
        var object: [String: Any] = ["type": type, "message": content]
        object["timestamp"] = stamp
        object["cwd"] = cwd
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static func read(_ id: String, _ file: String) -> [String: Any] {
        ["type": "tool_use", "id": id, "name": "Read", "input": ["file_path": file]]
    }

    private static func failure(_ id: String) -> [String: Any] {
        ["type": "tool_result", "tool_use_id": id, "is_error": true, "content": "boom"]
    }

    private static func replay(_ lines: [Data], in directory: URL) throws -> ContextReplay {
        let transcript = directory.appendingPathComponent("session.jsonl")
        try Data(lines.flatMap { $0 + [0x0A] }).write(to: transcript)
        let probes = ReplayProbes(since: nil, until: nil, timeZone: .gmt, belowFloor: { _ in false }, couldAnswer: { _, _ in true }, memberExists: { _, _, _ in true })
        return TranscriptReplay.replay(transcript, session: transcript, isSubagent: false, probes: probes, hook: PassingHook())
    }

    /// A Read at 23:59 whose failing result lands after midnight is taken back on the day of the call, so the day of the result is left with nothing.
    @Test
    func aFailedCallStraddlingMidnightIsTakenBackOnTheDayOfTheCall() throws {
        let directory = try TemporaryDirectory.make("replay-correction-day")
        let file = directory.appendingPathComponent("Catalogue.swift").path
        let context = try Self.replay([
            Self.line("assistant", at: "2026-10-06T23:59:00Z", cwd: directory.path, block: Self.read("r1", file)),
            Self.line("user", at: "2026-10-07T00:00:30Z", cwd: nil, block: Self.failure("r1")),
        ], in: directory)

        #expect(context.byDay["2026-10-06"]?.cold == 0, "\(context.byDay)")
        #expect(context.byDay["2026-10-07"]?.cold ?? 0 == 0, "\(context.byDay)")
        #expect(context.tally.cold == 0)
    }

    /// A call written with no time that then fails takes back a count no day holds: the dated call of another id keeps its own day's count, as the plain audit's tally keeps it.
    @Test
    func anUndatedCallsFailureIsFiledOnNoDay() throws {
        let directory = try TemporaryDirectory.make("replay-correction-undated")
        let dated = directory.appendingPathComponent("Dated.swift").path
        let undated = directory.appendingPathComponent("Undated.swift").path
        let context = try Self.replay([
            Self.line("assistant", at: "2026-10-06T10:00:00Z", cwd: directory.path, block: Self.read("d1", dated)),
            Self.line("assistant", at: nil, cwd: directory.path, block: Self.read("u1", undated)),
            Self.line("user", at: "2026-10-06T10:00:05Z", cwd: nil, block: Self.failure("u1")),
        ], in: directory)

        #expect(context.tally.cold == 1, "\(context.tally.cold)")
        #expect(context.byDay["2026-10-06"]?.cold == context.tally.cold, "\(context.byDay)")
    }

    /// A repeated id on an undated line leaves the earlier dated call's day unclaimed: the failure takes back the undated call's count, so a later call on the failure's day is counted there alone.
    @Test
    func aRepeatedIdOnAnUndatedLineIsFiledOnNoDay() throws {
        let directory = try TemporaryDirectory.make("replay-correction-repeat")
        let first = directory.appendingPathComponent("First.swift").path
        let second = directory.appendingPathComponent("Second.swift").path
        let later = directory.appendingPathComponent("Later.swift").path
        let context = try Self.replay([
            Self.line("assistant", at: "2026-10-09T10:00:00Z", cwd: directory.path, block: Self.read("r1", first)),
            Self.line("assistant", at: nil, cwd: directory.path, block: Self.read("r1", second)),
            Self.line("user", at: "2026-10-10T10:00:00Z", cwd: nil, block: Self.failure("r1")),
            Self.line("assistant", at: "2026-10-10T11:00:00Z", cwd: directory.path, block: Self.read("r2", later)),
        ], in: directory)

        #expect(context.byDay["2026-10-10"]?.cold == 1, "\(context.byDay)")
    }

    /// An earlier call of a turn scored as answered is scored again once its sibling's result says the hook let it through; that rescore, on a result line after midnight, is filed under the day of the call in the replayed count as in the tally.
    @Test
    func aRescoreStraddlingMidnightIsReplayedOnTheDayItIsTalliedOn() throws {
        let directory = try TemporaryDirectory.make("replay-correction-rescore")
        try "struct Widget {}\n".write(to: directory.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        let search: [String: Any] = ["output_mode": "content", "pattern": "UsageWindow", "glob": "*.swift"]
        func grep(_ id: String) -> [String: Any] {
            ["type": "tool_use", "id": id, "name": "Grep", "input": search]
        }
        func answer(_ id: String) -> [String: Any] {
            ["type": "tool_result", "tool_use_id": id, "content": "Sources/App/Usage.swift"]
        }
        let context = try Self.replay([
            Self.line("assistant", at: "2026-10-06T23:59:00Z", cwd: directory.path, block: grep("g1"), message: "m1"),
            Self.line("assistant", at: "2026-10-06T23:59:10Z", cwd: directory.path, block: grep("g2"), message: "m1"),
            Self.line("user", at: "2026-10-06T23:59:20Z", cwd: nil, block: answer("g1")),
            Self.line("user", at: "2026-10-07T00:00:30Z", cwd: nil, block: answer("g2")),
        ], in: directory)

        let tallied = context.byDay.mapValues(\.cold)
        let replayed = context.replayByDay.mapValues { $0.stillCold.values.reduce(0, +) + $0.recovered.values.reduce(0, +) }

        #expect(tallied == ["2026-10-06": 2], "\(tallied)")
        #expect(replayed == tallied, "\(replayed) against \(tallied)")
    }
}

extension ReplayCorrectionDayTests {
    /// A hook that lets every call through.
    private final class PassingHook: ReplayHook {
        func verdict(payload _: [String: Any], cwd _: String, at _: Date?, decides _: Bool) -> ReplayVerdict? {
            ReplayVerdict(token: "allowed", rule: "noLookup")
        }

        func answered(payload _: [String: Any], cwd _: String, at _: Date?) {}

        func locatedOnlyByAnswers(_: String, payload _: [String: Any]) -> Bool {
            false
        }
    }
}
