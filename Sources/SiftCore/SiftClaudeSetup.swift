//
// Copyright © Agulhas Labs
//

import Fieldwork

/// What SwiftSure registers with Claude Code, as values for the shared Fieldwork library: the hook events and their matchers, the MCP server, and the agent rule.
///
/// The library does the registering; this is the one place that says what SwiftSure registers, so its identity is spelled once.
public struct SiftClaudeSetup {
    /// The session-start hook's own matchers.
    ///
    /// `clear` and `compact` earn their place alongside `startup` and `resume` for the same reason: each discards the context, which discards the primer with it, and the session goes on to do exactly the Swift work the primer exists for. A compaction is the one of the two nobody asks for — it arrives mid-task, and the primer survives it only if the summary happens to keep it.
    public static let sessionStartMatchers = ["startup", "resume", "clear", "compact"]

    /// Every event SwiftSure registers for, the subcommand each one runs, and the matchers each one needs.
    ///
    /// `SubagentStart` is here because a `SessionStart` hook does not fire for subagents and the path-scoped rule does not reach them either, which would leave the contexts doing the heaviest whole-file reading as the only ones getting no guidance at all. It takes no matcher: there is nothing to match on, and an entry without the key fires for every subagent.
    ///
    /// `PreToolUse` is a different job by a different command. Its matcher names every tool that can read Swift source, because a `PreToolUse` hook without a matcher runs on every tool call. Matchers are anchored, not substring, so the Xcode server's read tools are spelled out. This server's own tools and writes are here to be observed rather than judged: a hook payload names the conversation, which a log line does not.
    ///
    /// `PostToolUse` is the other side of the same edit, a nudge rather than an answer, and it reads the answer of a `digest` and the output of a `Grep` or `Bash` call too. Its timeout is shorter because it runs after the tool already ran.
    ///
    /// `Stop` and `SubagentStop` are the end of the same work, a gate rather than a nudge: one command serves both, and neither takes a matcher.
    public static let events: [HookRegistration.Event] = [
        HookRegistration.Event(name: "SessionStart", subcommand: sessionStartSubcommand, matchers: sessionStartMatchers, timeout: 5),
        HookRegistration.Event(name: "SubagentStart", subcommand: sessionStartSubcommand, matchers: [], timeout: 5),
        HookRegistration.Event(
            name: "PreToolUse",
            subcommand: preToolUseSubcommand,
            matchers: ["Bash|Read|Grep|Glob|mcp__xcode__Xcode(Read|Grep|Glob)|\(ProductName.current.toolPrefix).*|\(ProductName.current.pluginToolMatcher(".*"))|Write|Edit|MultiEdit"],
            timeout: 5
        ),
        HookRegistration.Event(
            name: "PostToolUse",
            subcommand: "post-tool-use",
            matchers: ["Write|Edit|MultiEdit|\(ProductName.current.toolPrefix)digest|\(ProductName.current.pluginToolMatcher("digest"))|Grep|Bash"],
            timeout: 3
        ),
        HookRegistration.Event(name: "PostToolUseFailure", subcommand: "post-tool-use", matchers: ["Bash"], timeout: 3),
        HookRegistration.Event(name: "Stop", subcommand: "stop", matchers: [], timeout: 5),
        HookRegistration.Event(name: "SubagentStop", subcommand: "stop", matchers: [], timeout: 5),
    ]

    /// The subcommands of the advice hooks, the ones a user can remove alone.
    public static let adviceSubcommands: Set<String> = [preToolUseSubcommand]

    /// The subcommand of the `PreToolUse` hook, the advice hook.
    public static var preToolUseSubcommand: String {
        "pre-tool-use"
    }

    /// The subcommand of the session-start hook, which also serves `SubagentStart`.
    public static var sessionStartSubcommand: String {
        "session-start"
    }

    /// The npm package an earlier release's MCP registration ran through `npx`; uninstall still recognises it.
    public static var npmPackage: String {
        ProductName.npmPackage
    }

    /// The hooks SwiftSure registers in a Claude Code `settings.json`.
    public static let hooks = HookRegistration(tool: .sift, events: events)

    /// The hooks as `name`'s binary registers them: what an earlier release left in a settings file is found and removed through the registration of the name it shipped under.
    public static func hooks(named name: ProductName) -> HookRegistration {
        HookRegistration(tool: FieldworkTool(name: name.binary, hookSubcommands: events.map(\.subcommand)), events: events)
    }

    /// The registration of every name in `names`, in the order given.
    public static func hooks(recognising names: [ProductName]) -> [HookRegistration] {
        names.map { hooks(named: $0) }
    }

    /// The user-scope MCP server as `name`'s binary registers it, for the removal of one an earlier release left.
    public static func server(named name: ProductName) -> ClaudeMcpServer {
        ClaudeMcpServer(tool: FieldworkTool(name: name.binary), arguments: ["mcp"], npmPackage: npmPackage, removal: .userScope)
    }

    /// A Claude Code doctor for each name the build answers to, current first: what an earlier release left in the settings is found through the registration of the name it shipped under.
    public static func doctors(environment: [String: String], probe: DoctorProbe, expectedTools: [String]) -> [DoctorClaude] {
        ProductName.recognised.map { name in
            DoctorClaude(environment: environment, probe: probe, hooks: hooks(named: name), server: server(named: name), expectedTools: expectedTools)
        }
    }

    /// The user-scope MCP server SwiftSure registers, removed at user scope only.
    public static let server = ClaudeMcpServer(tool: .sift, arguments: ["mcp"], npmPackage: npmPackage, removal: .userScope)

    /// The MCP server half of the install.
    public static let mcp = ClaudeMcpInstall(server: server)

    /// The agent rule: the `SwiftSure.md` that ships beside the binary, loaded on Swift files.
    public static let rule = ClaudeRuleInstall(tool: .sift, shippedFileName: ProductName.current.ruleFileName, shareDirectory: ProductName.current.shareDirectory, loadsOn: "**/*.swift")
}
