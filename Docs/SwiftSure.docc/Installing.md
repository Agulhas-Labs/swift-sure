# Installing

Set SwiftSure up in Claude Code, Cursor and Codex with one command, and take it out again.

## Overview

With `swift-sure` on your `PATH` (see <doc:GettingStarted>: install it with Homebrew, or build it from
source and copy the binary there), one command sets it up in every agent you use:

```sh
swift-sure install
```

It looks for Claude Code (`claude` on the `PATH`, or `~/.claude`), Cursor (`~/.cursor`, or Cursor.app) and
Codex (`codex` on the `PATH`, `$CODEX_HOME`, or `~/.codex`), lists what it found and the files it would
write, and asks once per agent found. Re-running it is safe: a second run changes nothing and says so, and
it is also the upgrade path.

To see what it would do first, ask for a dry run. This writes nothing and runs neither `claude` nor
`codex`. This is the Claude Code part of its answer from a binary with no `SwiftSure.md` beside it (a source build, say), on a machine where only the rule is in place, abridged:

```text
$ swift-sure install --dry-run --agent claude
Claude Code: found — `claude` on PATH
    would write ~/.claude/settings.json (hooks)
    would write ~/.claude.json (the MCP server at user scope, through `claude mcp add`)
    left as installed ~/.claude/rules/swift-sure.md (the agent rule) — no SwiftSure.md ships beside this binary to refresh it from (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)
…
Claude Code MCP server: would register ~/.local/bin/swift-sure mcp through `claude mcp add`
Claude Code rule: left as installed — no SwiftSure.md ships beside this binary to refresh it from (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)
dry run: nothing written and nothing run; without --dry-run this installs into Claude Code
```

Four flags answer or preview the questions:

| Flag | Does |
|---|---|
| `--yes` | install into every agent found, without asking |
| `--all` | install into all three, found or not, without asking |
| `--agent claude\|cursor\|codex` | install into that one, found or not, without asking; repeat for more |
| `--dry-run` | say what was found and what would be written |

With no terminal to ask on, it installs nothing unless `--yes`, `--all` or `--agent` says what to install
into, and says so. One agent's failure is reported and the others still install. It ends with a summary of
what was written for each agent, the one manual step, and what is unsupported there.

If you already manage Claude Code through plugin marketplaces, a SwiftSure plugin for Claude Code is the other
route. It is not published yet, so `swift-sure install` is the one that works today.

## Claude Code

**What is written:**

- the hooks, in `~/.claude/settings.json`
- the MCP server at user scope, through `claude mcp add`
- the agent rule, at `~/.claude/rules/swift-sure.md`, which keeps itself out of context unless Swift is in play.
  This one is written only where a `SwiftSure.md` ships with the binary, and a source build has none (below).

The merge into `settings.json` preserves every other key and hook, refuses a file that will not parse, and
copies it to `settings.json.bak-swift-sure` first.

**The one manual step:** start a new Claude Code session, for the session primer, the tool list and the rule file, which load at session start. On an upgrade a running session's server re-executes into the replaced binary before its next request and the hooks apply at once; after a first install there is no SwiftSure server in it yet.

**From a source build:** `swift-sure install` registers the path of the binary you ran, so run it as `swift-sure` from
the copy on your `PATH` (see <doc:GettingStarted>) and not from `.build/release`. It writes the hooks and
the MCP server as above. It does not write the agent rule: nothing ships a `SwiftSure.md` beside a
source build, so the install prints ``rule: skipped — no SwiftSure.md ships with this binary (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)`` and goes on. The
file is in the root of the source tree; to add the rule, copy it to `~/.claude/rules/swift-sure.md` yourself.

**Uninstall:**

```sh
swift-sure uninstall
```

This takes out the hooks, a legacy sift status line, the MCP server and the agent rule, and lists the `.swift-sure/`
directories it leaves behind. It deletes nothing from a repository unless you add `--purge`, which also
deletes every index, run log and usage log. The binary stays: the last line it prints is the command that
removes it, by how it was installed. To remove only the hooks, use `swift-sure uninstall-hook`.

## Cursor (experimental)

Support for Cursor is experimental until its live test is finished.

**What is written:** two files and nothing else. `~/.cursor/mcp.json` holds the MCP server, and
`~/.cursor/hooks.json` holds the `sessionStart`, `preToolUse` and `postToolUse` hooks. A `.bak-swift-sure` copy of
a file is kept before any rewrite, and entries that are not SwiftSure's are left alone.

**The one manual step:** restart Cursor.

**Not supported on Cursor:** `swift-sure audit`, a subagent primer, and a machine-wide
Swift-scoped rule.

**Uninstall:**

```sh
swift-sure uninstall-hook --agent cursor
```

This takes exactly those entries back out. `swift-sure uninstall` does so too.

## Codex (experimental)

Support for Codex is experimental until its live test is finished.

**What is written:** `hooks.json` in the Codex home, holding the `SessionStart`, `PreToolUse` and
`PostToolUse` hooks, and the MCP server, registered through `codex mcp add`. When `codex` is not on the
`PATH`, the command is printed for you to run instead. The Codex home is `--codex-dir`, then `$CODEX_HOME`,
then `~/.codex`, and the install names the directory it wrote. A `.bak-swift-sure` copy of `hooks.json` is kept
before any rewrite.

**The one manual step:** restart Codex. It shows a trust prompt for the SwiftSure hooks the first time it opens,
and they run once you approve it. You can also review them later in `/hooks`.

**Not supported on Codex:** `swift-sure audit`, a Swift-scoped rule, and the subagent primer.
A lookup the Codex CLI runs inside its sandbox is not counted in the usage log, so `swift-sure usage` undercounts
Codex use.

**Uninstall:**

```sh
swift-sure uninstall-hook --agent codex
```

This takes exactly those entries back out. `swift-sure uninstall` does so too.

## Next steps

The guide has the full reference for
[`swift-sure install`](https://github.com/Agulhas-Labs/swift-sure/blob/main/Docs/Guide.md#swift-sure-install), the hooks, and
the per-agent mechanics for
[Cursor](https://github.com/Agulhas-Labs/swift-sure/blob/main/Docs/Guide.md#cursor-swift-sure-install-hook---agent-cursor-experimental)
and
[Codex](https://github.com/Agulhas-Labs/swift-sure/blob/main/Docs/Guide.md#codex-swift-sure-install-hook---agent-codex-experimental).
