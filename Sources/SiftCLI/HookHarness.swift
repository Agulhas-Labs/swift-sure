//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import SiftMCP

/// What the `pre-tool-use` hook reads and prints in the protocol of the harness it is registered for, Claude Code's or Cursor's.
struct HookHarness {
    /// The harness the hook is registered for.
    let agent: HookAgent

    /// The shell command passed on the command line, which skips the stdin payload.
    let command: String?

    /// Whether a probe asked for the terse verdict line instead of the hook's JSON.
    let verdict: Bool

    /// The payload the hook judges, in Claude Code's form, or `nil` where it prints nothing: a Cursor payload under the Claude Code registration, and one the Cursor registration cannot read.
    func read(_ payload: [String: Any]) -> [String: Any]? {
        switch agent {
        case .claude:
            return Self.standsAsideForCursor(payload, verdict: verdict) ? nil : payload
        case .cursor:
            guard let read = command == nil ? CursorPreToolUseHook.claudePayload(from: payload) : payload else {
                if verdict {
                    StandardStreams.emit(PreToolUseCommand.Verdict(token: "allowed", rule: "unread").line)
                }
                return nil
            }
            return read
        }
    }

    /// Whose rules decide that a build's rewrite costs no prompt: Claude Code's settings under Claude Code, and Cursor's own shell rules under Cursor, read for the directory the command runs in.
    var runPermission: (String?) -> WrappedRunPermission {
        guard agent == .cursor else { return WrappedRunPermission.standard(in:) }
        return { CursorShellPermission.load(directory: $0) }
    }

    /// Prints the hook's `output` in the protocol of the harness it is registered for: as written for Claude Code, and read into Cursor's schema for Cursor, where what that schema cannot carry prints nothing.
    func answer(_ output: String, payload: [String: Any]) {
        CursorPreToolUseHook.deliver(
            output, payload: payload, agent: agent,
            emit: { StandardStreams.emit($0) },
            file: { CursorPreToolUseHook.fileNotice(output: $0, response: $1, payload: payload) }
        )
    }

    /// Whether the hook answered the shell line `payload` carries with its trim (``InPlaceBuildRewrite/trimmed(shell:payload:in:agent:readingPermission:)``), printing the amendment, or its verdict for a probe; `false`, with nothing printed, wherever the line is no trimmable pipe or the trim could cost a prompt.
    func answersATrim(payload: [String: Any], in directory: String?) -> Bool {
        guard command != nil || payload["tool_name"] as? String == "Bash",
              let trimmed = InPlaceBuildRewrite.trimmed(shell: PreToolUseCommand.shellText(command: command, payload: payload), payload: payload, in: directory, agent: agent, readingPermission: { runPermission(directory) })
        else { return false }
        if verdict {
            StandardStreams.emit(trimmed.verdict.line)
        } else if let json = trimmed.json {
            answer(json, payload: payload)
        }
        return true
    }

    /// Whether `payload` is Cursor's, which shows a refusal to the user rather than the model (`CursorHookPayload`), so the hook prints nothing; a probe is told why.
    private static func standsAsideForCursor(_ payload: [String: Any], verdict: Bool) -> Bool {
        guard CursorHookPayload.recognises(payload) else { return false }
        if verdict {
            StandardStreams.emit(PreToolUseCommand.Verdict(token: "allowed", rule: "cursor").line)
        }
        return true
    }
}
