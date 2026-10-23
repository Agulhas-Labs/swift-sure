//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import SiftMCP

/// The hook's in-place rewrite of a raw build to its `swift-sure run --` wrapping, judged against Claude Code's permission rules or Cursor's.
struct InPlaceBuildRewrite {
    /// A build rewritten in place to its `swift-sure run --` wrapping, a build let through untouched because the user's own ask or deny rule speaks for the line or the shell would not run the line as written, or `nil` where `lookup` is no build or the rewrite could cost the user a prompt.
    ///
    /// The command runs wrapped in the same turn, with no permission decision made here, so the user's own rules still apply — to the rewritten command, which is why the rewrite waits on ``SiftMCP/WrappedRunPermission``. It interrupts nothing, so it neither consults nor spends the ledger, and every run of the build is rewritten, the loop's repeats included.
    ///
    /// The line carries no mark of its own: the hook says in the `additionalContext` of the same output (``SiftCore/RunRewrite/notice(forCommand:)``, for the first wrapped statement) that it ran the build, and how to get the raw output. A word on the line would reach whichever `swift-sure` the shell resolves, and an older build rejects it; one put before the wrapped command would stop the allow rules `install-hook` writes matching.
    ///
    /// A line the shell would not run as written (``SiftMCP/ShellSyntax/isIncomplete(_:)``) is neither rewritten nor refused: the hook cannot know what the finished command will be, so a wrapping it named would be a guess at a line nobody wrote. It is let through as written.
    ///
    /// Where an ask or deny rule matches anything the line runs as written, the build is neither rewritten nor refused with its wrapping named: either would hand the model a command that rule, written for the original, does not match. It is let through, so Claude Code applies the rule to the command it was written for. So is every build while a settings file the hook cannot read is in the chain, since such a rule may be in it unseen.
    ///
    /// On Cursor (`agent`) the rules are Cursor's own shell rules (``SiftMCP/CursorShellPermission``), and a build is never `nil`, so never refused: a refusal there reached a model that re-ran the raw command instead of the wrapping. It is rewritten unless the rewrite adds a prompt the line as written would not meet — an allow rule covers the build as written and none covers the wrapping — and let through as written where it does, or where the line draws no in-place rewrite.
    static func decided(
        _ lookup: PreToolUseCommand.Lookup,
        shell: String?,
        payload: [String: Any],
        in directory: String?,
        suppressions: SuppressionLog,
        agent: HookAgent = .claude,
        readingPermission: () -> WrappedRunPermission
    ) -> (json: String?, verdict: PreToolUseCommand.Verdict)? {
        guard lookup.rule == "RunAdvice", let shell else { return nil }
        let permission = readingPermission()
        let standAside = permission.hasUnreadableSettings ? "unreadable-settings"
            : permission.vetoes(line: shell) ? "vetoed"
            : ShellSyntax.isIncomplete(shell) ? "incomplete" : nil
        if let standAside {
            suppressions.note(symbol: nil, directory: directory, rule: standAside)
            return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: standAside))
        }
        guard agent == .cursor else {
            guard let rewrite = RunAdvice.inPlaceRewrite(of: shell),
                  permission.addsNoPrompt(legs: rewrite.legs, mode: payload["permission_mode"] as? String)
            else { return nil }
            return amended(lookup, rewrite: rewrite, payload: payload)
        }
        guard let rewrite = RunAdvice.inPlaceRewrite(of: shell) else {
            suppressions.note(symbol: nil, directory: directory, rule: "unwrappable")
            return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: "unwrappable"))
        }
        // A deny rule may name the wrapping itself (`Shell(swift-sure)`): Cursor would refuse the rewritten line where the
        // line as written runs, so the line runs as written.
        if permission.vetoes(line: rewrite.line) {
            suppressions.note(symbol: nil, directory: directory, rule: "vetoed")
            return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: "vetoed"))
        }
        guard CursorShellPermission.addsNoNewPrompt(permission, legs: rewrite.legs) else {
            suppressions.note(symbol: nil, directory: directory, rule: "adds-prompt")
            return (nil, PreToolUseCommand.Verdict(token: "allowed", rule: "adds-prompt"))
        }
        return amended(lookup, rewrite: rewrite, payload: payload)
    }

    /// The hook's output for a build rewritten in place to `rewrite`'s line: the whole tool input sent back with the command replaced, and the notice naming what ran.
    private static func amended(_ lookup: PreToolUseCommand.Lookup, rewrite: (line: String, legs: [String]), payload: [String: Any]) -> (json: String?, verdict: PreToolUseCommand.Verdict) {
        var input = payload["tool_input"] as? [String: Any] ?? [:]
        input["command"] = rewrite.line
        let note = rewrite.legs.first.map { RunRewrite.notice(forCommand: String($0.dropFirst(IndexSuggestion.toolchainRunPrefix.count))) }
        return (
            HookOutput.preToolUseAmendment(input: input, context: note),
            PreToolUseCommand.Verdict(token: "amended", call: TerseCall.call(for: lookup.suggestion, serverGone: false), rule: lookup.rule)
        )
    }
}
