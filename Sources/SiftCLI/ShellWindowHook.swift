//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import SiftMCP

/// The hook's part in answering a shell window with its own lines, comment runs folded (``SiftMCP/ShellWindowFold``): which lines go to that answer, and the verdict each gets.
///
/// A shell window is never answered with a digest.
struct ShellWindowHook {
    /// The call's payload, in Claude Code's form.
    let payload: [String: Any]
    let session: String?
    let context: AdviceContext
    let directory: String?
    let ledger: AdviceLedger
    let usage: UsageLog?
    let suppressions: SuppressionLog

    /// `classified`, a shell lookup, carrying the line the fold reads and the windows `located` does not locate, where `shell` reads a Swift file through such a window (``unlocatedWindows(in:from:located:)``); `nil` for every other lookup.
    ///
    /// The lookup is otherwise as classified, so where the ledger turns out to locate every one of those windows, it goes the way every located window does.
    static func lookup(_ classified: PreToolUseCommand.Lookup, shell: String?, in directory: String?, located: (String, [LineWindow]) -> Bool) -> PreToolUseCommand.Lookup? {
        guard classified.rule == "ShellAdvice", let shell, let found = unlocatedWindows(in: shell, from: directory, located: located) else { return nil }
        var lookup = classified
        lookup.shellWindows = found.line
        lookup.unlocatedShellWindows = found.unlocated
        return lookup
    }

    /// The decision on `lookup` where it reads a shell window, or `nil` where every other gate decides it: the fold's verdict where a window is left unlocated (``decided(_:lookup:shell:)``), and otherwise, every window located, the reading the line had before the fold, its withholdings noted, put in `lookup`'s place (a reading that gave no lookup lets the call through).
    func decided(routing lookup: inout PreToolUseCommand.Lookup, shell: String?) -> (json: String?, verdict: PreToolUseCommand.Verdict)? {
        guard let line = lookup.shellWindows else { return nil }
        guard Self.locatesEveryWindow(of: lookup, ledger: ledger, session: context.key) else { return decided(line, lookup: lookup, shell: shell) }
        guard let ordinary = lookup.ordinaryReading?.taken(noting: suppressions) else { return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: "noLookup")) }
        lookup = ordinary
        return nil
    }
}

extension ShellWindowHook {
    /// The reading the hook gave a line before the fold existed, every gate of ``PreToolUseCommand/lookup(command:payload:in:noting:digested:couldAnswer:resolvingDigests:allowed:folding:)`` met, with the withholdings it logged held back: the line's reading where the ledger locates every window the usage log did not.
    final class OrdinaryReading: Sendable {
        /// The lookup that reading gave, `nil` where it gave none.
        let lookup: PreToolUseCommand.Lookup?
        let rows: SuppressionLog.Deferred

        init(lookup: PreToolUseCommand.Lookup?, rows: SuppressionLog.Deferred) {
            self.lookup = lookup
            self.rows = rows
        }

        /// `folded`, carrying what `reading` gives with its withholdings held back.
        static func carried(by folded: PreToolUseCommand.Lookup, reading: (SuppressionLog) -> PreToolUseCommand.Lookup?) -> PreToolUseCommand.Lookup {
            let rows = SuppressionLog.Deferred()
            var carrying = folded
            carrying.ordinaryReading = OrdinaryReading(lookup: reading(SuppressionLog(deferringTo: rows)), rows: rows)
            return carrying
        }

        /// `lookup`, its withholdings noted in `suppressions` now that it is the reading taken.
        func taken(noting suppressions: SuppressionLog) -> PreToolUseCommand.Lookup? {
            suppressions.replay(rows)
            return lookup
        }
    }

    /// Whether the ledger locates every window of `lookup` the usage log did not, for `session`'s context, so the line goes the way every located window does rather than to the fold.
    static func locatesEveryWindow(of lookup: PreToolUseCommand.Lookup, ledger: AdviceLedger, session: String) -> Bool {
        lookup.unlocatedShellWindows.allSatisfy { heldByLedger($0.path, through: [$0.window], ledger: ledger, session: session) }
    }

    /// Whether the usage log of the call's context locates the file at `path` for `windows`: a window no wider than ``SiftMCP/ListedWindow/widestExcused`` by any answer that located the file, a wider one only by its whole digest.
    ///
    /// A call with no session locates nothing.
    static func locatedByUsage(_ path: String, through windows: [LineWindow], payload: [String: Any], digested: DigestedFiles, resolve: (String, String) -> String?) -> Bool {
        guard let session = payload["session_id"] as? String else { return false }
        let agent = payload["agent_id"] as? String
        guard digested.locates(path, session: session, agent: agent, resolve: resolve) else { return false }
        return !ListedWindow.isWide(windows, ofFileAt: path) || digested.contains(path, session: session, agent: agent, resolve: resolve)
    }

    /// The line `shell` is, read leg by leg, and the windows on it `located` does not locate, each by its file resolved against `directory`, where there is at least one; `nil` where the line goes the way every other lookup does.
    ///
    /// A window reaching every line of its file is a whole read: a leg beside the windows, like any other, and a line of nothing but such reads goes the way a whole read does. A line naming a file that cannot be read goes the way it always did, since nothing on disk says whether its window is a whole read.
    static func unlocatedWindows(in shell: String, from directory: String?, located: (String, [LineWindow]) -> Bool) -> (line: ShellWindowLine, unlocated: [(path: String, window: LineWindow)])? {
        guard let read = ShellWindowLine.readingAnyJoin(ShellInspection.withoutPassThroughTees(shell)) else { return nil }
        let resolved = { (window: ShellWindowLine.Window) in SwiftTree.resolve(readPath: window.path, relativeTo: directory) ?? window.path }
        guard read.windows.allSatisfy({ lineCount(ofFileAt: resolved($0)) != nil }) else { return nil }
        let line = read.reading(asOther: { !$0.catsSeveralFiles && readsWhole($0.window, ofFileAt: resolved($0)) })
        let unlocated: [(path: String, window: LineWindow)] = line.windows.map { (path: resolved($0), window: $0.window) }.filter { !located($0.path, [$0.window]) }
        guard !unlocated.isEmpty else { return nil }
        return (line: line, unlocated: unlocated)
    }

    /// Whether the ledger locates the file at `path` for `windows`, as the hook's own answers and index calls noted them, or holds it as written by `session`'s context.
    ///
    /// A digest that only locates the file excuses a window no wider than ``SiftMCP/ListedWindow/widestExcused``; a wider one needs the file's whole digest.
    static func heldByLedger(_ path: String, through windows: [LineWindow], ledger: AdviceLedger, session: String) -> Bool {
        if ledger.holds(path, session: session) {
            return true
        }
        let digests = ledger.digests(session: session)
        return ListedWindow.isWide(windows, ofFileAt: path) ? DigestedFiles.isDigested(path, among: digests) : DigestedFiles.isLocated(path, among: digests)
    }

    /// The verdict for `line`: let through as `windowBeside` where a leg on it is not a window or an `echo`, before the ledger is asked, so it spends no budget, unless a window's file holds a conflict marker or a parse error, which no answer could serve, so the line is not a miss; otherwise answered in place with the fold, or let through under the rule that withholds the fold, each logged against the call's id.
    ///
    /// The ledger knows the line by its whole text, `tee`s taken out, as the fold answers the whole line. A fold locates nothing, so the ledger notes no digest of the file and a later window of it is weighed again; the identical re-run is allowed, as after every answer in place.
    func decided(_ line: ShellWindowLine, lookup: PreToolUseCommand.Lookup, shell: String?) -> (json: String?, verdict: PreToolUseCommand.Verdict) {
        let call = payload["tool_use_id"] as? String
        let key = shell.map { AdviceLedger.key(forShell: ShellInspection.withoutPassThroughTees($0)) } ?? lookup.key
        let withheld = { (rule: String) -> (json: String?, verdict: PreToolUseCommand.Verdict) in
            suppressions.note(symbol: rule, directory: directory, rule: "answerWithheld", call: call)
            return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: rule))
        }
        guard !line.runsOthers else {
            return withheld(ShellWindowFold.unservable(line, in: directory, parsesWithError: ShellWindowFold.indexedWithParseError) ?? InPlaceAnswerer.Withholding.windowBeside.rawValue)
        }
        guard ledger.decide(session: context.key, command: key) != .allow else { return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: "ledger")) }
        // The answer runs nothing, so a file a `tee` on the line would write is not written, and the fold does not say so.
        if let shell, !ShellInspection.passThroughTeeFiles(shell).isEmpty {
            return withheld(InPlaceAnswerer.Withholding.notExact.rawValue)
        }
        let started = Date()
        switch ShellWindowFold.answer(line, in: directory, parsesWithError: ShellWindowFold.indexedWithParseError) {
        case let .letThrough(rule):
            return withheld(rule)
        case let .answered(text, calls, source, served):
            guard ledger.noteDenial(session: context.key, command: key) else { return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: "ledger")) }
            // Every byte of the denial is charged to the first window's call, against every byte the line prints.
            let answered = InPlaceAnswerer.Answered(
                reason: text,
                calls: calls.enumerated().map { index, call in
                    InPlaceAnswerer.Call(
                        tool: "window",
                        target: String(call.dropFirst("window ".count)),
                        bytes: index == 0 ? AnswerBytes(served: served, source: source) : AnswerBytes(served: 0),
                        intercepted: .window
                    )
                },
                root: CallerRoot.root(forCallerIn: directory) ?? directory ?? "",
                milliseconds: Int(Date().timeIntervalSince(started) * 1000)
            )
            HookUsage(payload: payload, command: shell, session: session, context: context, directory: directory, ledger: ledger, usage: usage)
                .record(answered, resolvedNothing: false)
            return (
                HookOutput.preToolUseDenial(reason: text),
                PreToolUseCommand.Verdict(token: "in-place", call: calls.joined(separator: "; "), rule: "commentsFolded", reason: text)
            )
        }
    }

    /// `lookup` let through as `notExact`, logged against the call, where the answer it would be given, the fold having claimed no line, answers a shell window: a window of a file that reaches fewer than every line of it, or whose lines cannot be read off the command; `nil` for every other lookup.
    ///
    /// A window reaching every line is a whole read and goes the way one does; a `Read` window is no shell window.
    static func unclaimedWindow(_ lookup: PreToolUseCommand.Lookup, payload: [String: Any], in directory: String?, noting suppressions: SuppressionLog) -> (json: String?, verdict: PreToolUseCommand.Verdict)? {
        guard lookup.rule == "ShellAdvice", let match = lookup.inPlace, answersAWindow(match) else { return nil }
        let rule = InPlaceAnswerer.Withholding.notExact.rawValue
        suppressions.note(symbol: rule, directory: directory, rule: "answerWithheld", call: payload["tool_use_id"] as? String)
        return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: rule))
    }

    /// Whether `match` answers a window of a file that reaches fewer than every line of it, or whose lines cannot be read off the command.
    private static func answersAWindow(_ match: InPlaceShape.Match) -> Bool {
        match.windowReads.contains { read in
            guard !read.windows.isEmpty, !read.windows.contains(where: \.isReadTool) else { return false }
            guard let count = lineCount(ofFileAt: read.path) else { return true }
            let printed = read.windows.map { $0.lines(inFileOf: count) }
            return printed.contains(nil) || Set(printed.compactMap(\.self).joined()).count < count
        }
    }

    /// Whether `window` prints every line of the file at `path`, which makes it a whole read.
    private static func readsWhole(_ window: LineWindow, ofFileAt path: String) -> Bool {
        guard let count = lineCount(ofFileAt: path) else { return false }
        return window.lines(inFileOf: count)?.count == count
    }

    /// How many lines the file at `path` holds, a last line with no newline included, or `nil` where it cannot be read.
    private static func lineCount(ofFileAt path: String) -> Int? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard !data.isEmpty else { return 0 }
        return data.count(where: { $0 == UInt8(ascii: "\n") }) + (data.last == UInt8(ascii: "\n") ? 0 : 1)
    }
}
