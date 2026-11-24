//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import SiftMCP

/// The parse check for a `Bash` call: every Swift file in the repository that changed since the call began, checked as an edit made with the Edit or Write tool is.
///
/// The command is never read, since a command parser misses `xargs sed -i` and a script that writes the file. What identifies the call's edits is the clock: the call began when Claude Code wrote the assistant message holding its `tool_use`, and a file whose change time is later is one the call, or something running beside it, changed.
struct BashEditParseCheck {
    private init() {}

    /// How much of the transcript's end is read to find the call's `tool_use` entry.
    static let tailBytes = 1 << 20

    /// The time the call with `toolUseID` began, from the transcript at `path`, or `nil` where its entry is not in the transcript's last ``tailBytes``.
    static func windowStart(transcriptPath path: String, toolUseID: String) -> Date? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        let needle = Data("\"\(toolUseID)\"".utf8)
        for line in lines.reversed() where line.range(of: needle) != nil {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let content = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]],
                  content.contains(where: { $0["type"] as? String == "tool_use" && $0["id"] as? String == toolUseID }),
                  let stamp = entry["timestamp"] as? String
            else { continue }
            return date(from: stamp)
        }
        return nil
    }

    private static func date(from stamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: stamp) {
            return parsed
        }
        return ISO8601DateFormatter().date(from: stamp)
    }

    /// The absolute paths of the Swift files under `root`, tracked or untracked and not ignored, that changed at or after `start`, sorted.
    static func changedSwiftFiles(under root: String, since start: Date) -> [String] {
        ChangedSwiftFiles.under(root, changedWithin: [start.timeIntervalSince1970 ... .greatestFiniteMagnitude])
    }

    /// How one Swift file is parsed: the seam a test slows or counts the checks through.
    typealias FileParse = @Sendable (_ file: String, _ root: String) -> EditParseCheck?

    /// The parse the hook runs on each changed file.
    static let standardParse: FileParse = { file, root in
        EditParseCheck.run(file: file, root: root, prior: .unknown, hunks: [])
    }

    /// How long past its own deadline the check waits for a file already being parsed.
    static let grace: TimeInterval = 0.1

    /// The hook JSON blocking on the Swift files a `Bash` call left unparseable, or `nil` where it left none, where each has been blocked already, or where the call's start cannot be found.
    ///
    /// One block names every failing file, each reason as the Edit check words it, separated by a blank line. A file counts against the once-per-content mark only when it is named. The check takes half of `timeBudget`, so the diagnostics note has the rest, and the files found broken before then still block.
    static func block(for payload: [String: Any], marks: HookMarks, timeBudget: TimeInterval, parse: @escaping FileParse = standardParse) -> String? {
        guard payload["tool_name"] as? String == "Bash",
              let toolUseID = payload["tool_use_id"] as? String,
              let sessionID = payload["session_id"] as? String,
              let sessionTranscript = payload["transcript_path"] as? String,
              let cwd = payload["cwd"] as? String
        else { return nil }
        let agentID = payload["agent_id"] as? String
        let transcript = ServerPresence.transcript(ofSession: sessionTranscript, agent: agentID) ?? sessionTranscript
        let share = timeBudget / 2
        let deadline = Date(timeIntervalSinceNow: share)
        let result = ResultBox<[Failure]>()
        result.value = []
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            failures(transcript: transcript, toolUseID: toolUseID, cwd: cwd, deadline: deadline, parse: parse, into: result)
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + share + grace)
        guard let failed = result.value, !failed.isEmpty else { return nil }
        let context = AdviceContext.resolve(sessionID: sessionID, transcriptPath: sessionTranscript, agentID: agentID)
        let fresh = failed.filter { marks.claim(context: context.key, file: $0.file, declaration: "unparseable \($0.check.contentHash)") }
        guard !fresh.isEmpty else { return nil }
        return HookOutput.postToolUseBlock(reason: fresh.map(\.check.reason).joined(separator: "\n\n"))
    }

    /// Parses the Swift files the call changed, in path order, until `deadline` by `now`, writing each failure into `result` as it is found so a caller that stops waiting keeps what was found.
    static func failures(
        transcript: String, toolUseID: String, cwd: String, deadline: Date, parse: FileParse, into result: ResultBox<[Failure]>, now: () -> Date = { Date() }
    ) {
        guard let start = windowStart(transcriptPath: transcript, toolUseID: toolUseID),
              let root = CallerRoot.root(forCallerIn: cwd)
        else { return }
        var found: [Failure] = []
        for file in changedSwiftFiles(under: root, since: start) {
            guard now() < deadline else { break }
            if let check = parse(file, root) {
                found.append(Failure(file: file, check: check))
                result.value = found
            }
        }
    }
}

extension BashEditParseCheck {
    /// A changed Swift file that does not parse, with its check.
    struct Failure {
        let file: String
        let check: EditParseCheck
    }
}
