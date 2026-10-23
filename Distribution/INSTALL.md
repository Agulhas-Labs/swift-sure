# SwiftSure — install

Two tools in one binary for AI coding agents working in Swift: build and test output an agent can
afford to read (`swift-sure run`, and hooks that answer a big file's whole read (about 12 KB and up in a typical 45k-token context, rising to about 20 KB by 120k, as it moves with the context; smaller files are read as asked) with its digest and check
every edit parses), and semantic lookups for when grep is too noisy (callers, read and write sites,
reference sweeps, structural search, string-catalog tracing) — as a CLI and an MCP stdio server.

<!-- PROVENANCE -->

## Is it earning its place?

Two commands, both read-only and local, meant to be pasted into a Claude session:

```sh
swift-sure audit --since today     # the share, and every lookup that went around the index, named
swift-sure usage --since today     # what was called, how fast, and what failed
```

`audit` answers "was this worth having"; `usage` is the call log behind it. Both are **pseudonymised
by default** (names become stable salted pseudonyms, counts stay), so a report is safe to paste anywhere;
`--unredact` prints the real names.

## What changed

`CHANGELOG.md`, in this bundle.

## License

Apache License 2.0 — `LICENSE.txt` in this bundle carries the text; the source is public. The
open-source components the binary links, and their licenses, are listed in `THIRD-PARTY-NOTICES.txt` beside it.

## What's in here

| File | |
|---|---|
| `swift-sure` | the binary — one file, no runtime, no package manager |
| `install.sh` | copies it to `~/.local/bin` and appends a line (time, version, commit or source tree, tree state, binary size) to `~/.swift-sure/deploys.jsonl` (`swift-sure report --deploys` lists them); then, where Claude Code is found (`claude` on the `PATH`, or its directory, `$CLAUDE_CONFIG_DIR` when set and `~/.claude` otherwise, exists), writes its rule, registers the hooks and registers the MCP server at user scope (a per-repository `claude mcp add --scope local` is an alternative to that, never a second step; see `Docs/Guide.md` §3) |
| `BUILD_INFO` | the version, build and tree state this bundle was built from, which `install.sh` records; without it the line carries `null` for them. The build is `commit`, the commit a release was cut from, or `sourceTree`, for a local build, the git tree hash of the source (a tree, not a commit); exactly one is present. `tree` is the clean or dirty state |
| `SwiftSure.md`, `README.md` | the agent guide and the overview |
| `Docs/Guide.md` | the full reference: config, indexing, freshness, troubleshooting, every command |

Installed with Homebrew, there is no `install.sh` or `BUILD_INFO`: the binary is linked into `$(brew --prefix)/bin`,
the documents are in `$(brew --prefix)/share/swift-sure`, and `swift-sure install` is the setup step.

## Requirements

- **Apple Silicon Mac, macOS 13+.** This build is arm64-only by design — no Intel slice.
- **Xcode or Command Line Tools.** Not for running the binary, but the semantic half resolves
  `libIndexStore.dylib` via `xcrun --find swift` at query time.
- **git.** A non-git directory is refused outright.

## Install

From this unpacked bundle, the first command is `sh install.sh` ("From this bundle" below says what it does):

```sh
sh install.sh
```

Installed with Homebrew, and for re-running later, it is `swift-sure install`:

```sh
swift-sure install
```

With `swift-sure` on your `PATH` (Homebrew puts it there; from this bundle, `sh install.sh` below does),
`swift-sure install` is the one command for all three agents. It looks for Claude Code (`claude` on the `PATH`, or
`~/.claude`), Cursor (`~/.cursor`, or Cursor.app) and Codex (`codex` on the `PATH`, `$CODEX_HOME`, or
`~/.codex`), lists what it found and the files it would write there, and asks once per agent found (default
yes). It runs the same installers as `install-hook`, so nothing new is written:

- **Claude Code:** the hooks in `~/.claude/settings.json`, the MCP server at user scope
  (through `claude mcp add`), and, where a `SwiftSure.md` ships beside the binary (Homebrew ships one, so `swift-sure install` from it writes the rule), the agent rule at
  `~/.claude/rules/swift-sure.md`; a bundle install gets the rule from `install.sh`. Then start a **new** session for the
  primer, the tool list and the rule.
- **Cursor:** `~/.cursor/mcp.json` and `~/.cursor/hooks.json`. Then restart Cursor.
- **Codex:** `hooks.json` in the Codex home and the MCP server (through `codex mcp add`). Then restart Codex; it
  shows a trust prompt for the hooks the first time it opens, and they run once you approve it.

| Flag | Does |
|---|---|
| `--yes` | install into every agent found, without asking |
| `--all` | install into all three, found or not, without asking |
| `--agent claude\|cursor\|codex` | install into that one, found or not, without asking; repeat for more |
| `--dry-run` | say what was found and what would be written; write nothing, and ask `simwalk`, if found, for its own dry run |

Where it installs Claude Code's hooks on a terminal, it also asks two questions about allow rules, the same two
`install-hook` asks: whether `swift-sure digest`, `where`, `search` and `strings` may run without a permission prompt
(`[Y/n]`, default yes: they write only SwiftSure's own index and caches, the
repository's `.swift-sure/` (and its `.git/info/exclude` entry) and `~/.swift-sure`, and run git with the repository's fsmonitor and git hooks switched off; a no is remembered in `~/.swift-sure`, and the question then defaults to no until a yes or `--allow-lookups`), then whether `swift-sure run -- swift build`,
`swift test`, `xcodebuild` and `swiftlint` may (`[y/N]`, default no: a build runs package manifests and build
plugins). Each adds only its own block. With no terminal neither is asked and nothing is added; the Claude Code
section names `swift-sure install-hook --allow-run` (both blocks) and `--allow-lookups` (the lookups alone), and
`--no-allow-run` adds neither. `swift-sure install --allow-run` and `swift-sure install --allow-lookups` answer for the Claude Code
step without a terminal (`--no-allow-run` is `install-hook` only).

With no terminal to ask on, it installs nothing unless `--yes`, `--all` or `--agent` says what to install into,
and says so. One agent's failure is reported and the others are still installed; the exit status is 1 when any
failed. It ends with one summary: what was written for each agent, the manual step above, and what is
unsupported there. Re-running is idempotent (a second run says there is nothing to do) and is the upgrade path.

Where `simwalk` is on the `PATH` or beside the binary, `swift-sure install` then runs one `simwalk install --yes` carrying an `--agent <agent>` for each agent picked
(with `--dry-run` under a dry run), including an agent whose own step failed, so the family is set up in one step.

The per-agent commands (`install-hook`, with `--agent cursor` or `--agent codex`) stay for scripting; the
sections below are their reference.

If you already manage Claude Code through plugin marketplaces, a SwiftSure plugin for Claude Code is the other
route. It is not published yet, so `swift-sure install` is the one that works today.

### From this bundle

```sh
sh install.sh
```

**From Claude Code, run it yourself.** In auto mode, Claude Code's permission classifier may refuse an agent
running `install.sh`: it edits the agent's own settings and installs a binary with no Developer ID signature.
That is the harness working as intended. Type it at the prompt with a leading `!` instead:

```
! sh install.sh --allow-run
```

A `!` command has no terminal either, so nothing is asked: `--allow-run` adds both blocks of allow rules (the
lookups and the wrapped builds), `--allow-lookups` the lookups alone, and with neither no rule is added and the
output names the command that adds them. Then start a new Claude Code session.

The MCP server is registered only where `claude` is on the `PATH`; the Claude desktop app's embedded CLI is not.
Where it is missing, `install.sh` prints the `claude mcp add …` command to run by hand, and running it is the fix.

Re-running it is the upgrade path. On a terminal its `install-hook` step asks the two allow-rule questions above
(lookups default yes, or no after a remembered no; builds default no). With no terminal, as when an agent runs it,
nothing is asked or added and the output names the command that adds the rules; `sh install.sh --allow-run` (both
blocks) or `sh install.sh --allow-lookups` (the lookups alone) answers up front, and is the one command to install
and allow. An agent installing for a user passes them only when the user asked for it. Any other flag is refused.
Where Claude Code is not found (no `claude` on the `PATH`, no Claude directory), `install.sh` installs the binary only, writes nothing under `~/.claude`, and points to `swift-sure install`. It registers Claude Code only; run `swift-sure install` afterwards for Cursor and
Codex. It strips the quarantine flag (the binary is ad-hoc signed, so an AirDropped copy would be refused), copies the new
binary to a temporary name beside the destination and then renames it over the old one (never copy over
the old inode: macOS SIGKILLs the result, exit 137, silently; the rename gives the new binary an inode of
its own, and there is never a moment with no binary), refreshes the user rule, and **removes any existing `swift-sure` MCP
registration before adding this one** (at user scope; for a per-repository registration use the `claude mcp add --scope local` command in `Docs/Guide.md` §3 instead, never as well, or the server is registered twice), since `claude mcp add` fails outright on a name that already
exists.

If an older install left a sift status line or the `sift-band@sift` plugin, `install.sh` removes them (the plugin
through `claude plugin uninstall` and `claude plugin marketplace remove`), then deletes the folder the band was
copied to (`~/.local/share/sift/sift-mod`) and the marketplace file beside it that named the band. If `claude` is missing or a `claude plugin` command fails, the installer
still succeeds and prints the commands to run by hand.

On an upgrade, a running Claude Code session's server re-executes into the new binary before its next request and
the hooks apply at once; after a first install, and for the session primer, the tool list and the rule file, start
a **new** session. In any Swift repo:

```sh
swift-sure status     # freshness, counts, module map, index-store discovery — the doctor
```

The first query indexes the repo (once, and longer on a large tree); there is no separate
setup step. On a large codebase, `swift-sure init` reports which files got their module from a
directory-name guess rather than a build file and proposes the `moduleMap` entries that fix it; run it
before trusting `digest <Module>`.

## The agent guide — nothing to wire, nothing to commit

Where Claude Code is found, `install.sh` puts `SwiftSure.md` at `~/.claude/rules/swift-sure.md`. It applies to every repo on the machine, and
its frontmatter (`paths: ["**/*.swift"]`) keeps it out of context unless Swift is in play. To share it
with a team instead, copy it to `.claude/rules/swift-sure.md` inside a repo and commit it.

### The session primer

The rule arrives on contact with a `.swift` file, one step *after* the raw read it exists to replace.
So `install.sh`, where Claude Code is found, also registers a `SessionStart` hook (`swift-sure session-start` in
`~/.claude/settings.json`) that Claude Code runs before the model's first turn. It prints nothing
unless the session is inside an indexed root, above several of them, or in a Swift repo that has never
been indexed; above several roots it names the ones a query can pass as `root:`.

```sh
swift-sure session-start --cwd .    # see what this directory would get
swift-sure install-hook             # re-register by hand (idempotent; re-run after moving the binary)
swift-sure uninstall-hook           # take it back out (--only-advice keeps the primer)
```

The hooks run the binary `install-hook` was started as: the path you typed, or for a bare `swift-sure` the one
your shell found on PATH, a link kept as the link (Homebrew's `/opt/homebrew/bin/swift-sure`, which survives an
upgrade, not the Cellar copy behind it), provided that is the file actually running; if PATH leads to a different `swift-sure`
(a relative PATH entry, a wrapper), the running binary's own path is used. Run it as the binary you want the hooks to use. A path with a
space in it (a `SWIFT_SURE_DEST` under `~/Library/Application Support`) is written single-quoted, so the shell
Claude Code runs each hook through reaches it; re-running `install-hook` repoints an older unquoted entry.
Run through `npx` it refuses, since a binary in npx's cache is replaced per version and the hooks would then exit 127:
install the binary (a source build, `install.sh` or Homebrew) and run `swift-sure install-hook` from that.

The merge into `settings.json` is done by the binary: it preserves every other key and hook, refuses
a file that will not parse, and copies it to `settings.json.bak-swift-sure` first (rewritten on every run
that changes something). Both commands write atomically. A `settings.json` that is a **symlink** (into
a dotfiles repository, say) **stays a link**: the file it leads to is the one rewritten, keeping its
permissions, with its `.bak-swift-sure` copy beside it, and the answer names both paths. A link that leads to
nothing is refused and nothing is written. If your machine manages `settings.json` centrally, keep the
rule and run `swift-sure uninstall-hook`, which leaves every other hook alone.

Cursor imports the hooks in `~/.claude/settings.json` by default, but it shows a hook's refusal to you
rather than the model. So every SwiftSure hook recognises Cursor's payload and prints nothing there (that empty output lets the call through in Cursor is unconfirmed; Settings → Agents → Third-Party Imports turns the import off).

## Cursor (experimental)

```sh
swift-sure install-hook --agent cursor      # register the server and the hooks in ~/.cursor
swift-sure uninstall-hook --agent cursor    # take exactly those back out (swift-sure uninstall does this too)
```

It writes two files and nothing else: `~/.cursor/mcp.json` (server `swift-sure`, the binary's absolute path, args
`["mcp"]`) and `~/.cursor/hooks.json` (`sessionStart`, `preToolUse`, `postToolUse` and `postToolUseFailure` entries, each running
`<binary> <subcommand> --agent cursor`). A `.bak-swift-sure` copy of a file is kept before any rewrite, entries that
are not SwiftSure's are left alone, and re-running is idempotent. Restart Cursor to load it. `--cursor-dir <dir>`
names a location other than `~/.cursor`; `swift-sure install --agent cursor --cursor-dir <dir>` takes it too.

The hook never refuses a `Read` on Cursor: its payload carries only the path, so a ranged read and an edit's own
Read-shaped event look like a whole-file read.

Not supported on Cursor, and the install says so: `swift-sure audit`, a subagent primer, and a
machine-wide Swift-scoped rule (Cursor's rules are per project).

**Cursor support is experimental.** It was probed on Cursor Agent CLI 2026.09.28 and used for one whole
session (install, lookups, edits and builds) on Cursor Agent CLI 2026.10.16; the IDE was probed only for allowed calls.

## Codex (experimental)

```sh
swift-sure install-hook --agent codex      # register the hooks and the server in the Codex home
swift-sure uninstall-hook --agent codex    # take exactly those back out (swift-sure uninstall does this too)
```

The Codex home is `--codex-dir <dir>`, then `$CODEX_HOME`, then `~/.codex`, and the answer names the directory
it wrote; `swift-sure install --agent codex --codex-dir <dir>` takes it too. Some setups, such as an app-managed
`CODEX_HOME`, may rewrite that directory: check the printed path.

It writes `hooks.json` there (`SessionStart`, `PreToolUse` and `PostToolUse` groups, each running the plain
`<binary> session-start`, `pre-tool-use` or `post-tool-use`) and registers the MCP server through
`codex mcp add swift-sure -- <binary> mcp`, or prints that line when `codex` is not on PATH. A `.bak-swift-sure` copy of
`hooks.json` is kept before any rewrite, entries and servers that are not SwiftSure's are left alone, and re-running
is idempotent.

Codex will not run the hooks until you trust them: restart Codex, and it asks you to trust the SwiftSure hooks the first
time it opens; approve them in that prompt, or later in `/hooks`, where they can be reviewed. It asks again after the binary is repointed;
removing our group ahead of a foreign one shifts the foreign one's trust position too. Under
`codex exec`, MCP calls need approval (`requires approval, but approval policy is never`), so headless use needs
an approval mode that allows them.

Not supported on Codex, and the install says so: `swift-sure audit`, a Swift-scoped rule (Codex's
`AGENTS.md` is machine-wide, so none is written), the subagent primer, and the post-edit note for a file
`apply_patch` moves (no payload of a move has been captured; one it adds or updates is checked). A lookup the
Codex CLI runs inside its sandbox is not counted in the usage log: the `workspace-write` sandbox cannot write
`~/.swift-sure`, and the CLI says nothing about it, so `swift-sure usage` and `swift-sure report` undercount Codex use.

**Codex support is experimental** until a live test is finished.

## Uninstall

```sh
swift-sure uninstall            # hooks, MCP server, agent rule (and a legacy status line or band plugin); lists the .swift-sure/ directories and run ledgers left
swift-sure uninstall --purge    # the same, and deletes those directories: every index, run log, usage log and recorded run proof
```

It takes out what `install.sh` put in: the hooks in `~/.claude/settings.json` (as
`uninstall-hook` does, which also removes a legacy sift status line), the MCP server at user scope and, run in each project's directory, at local scope (through `claude mcp remove swift-sure`), a legacy band plugin and its marketplace (through `claude plugin uninstall
sift-band@sift` and `claude plugin marketplace remove sift`, when registered), and `~/.claude/rules/swift-sure.md`. Without `--purge` it deletes nothing from a repository; it lists each `.swift-sure/`
it knows of, each of those repositories' run ledgers (`swift-sure/` under its git directory), and `~/.swift-sure`;
a home `SWIFT_SURE_HOME` (or `SIFT_HOME`) moved elsewhere is deleted by `--purge` only when it holds nothing but what swift-sure writes there;
`--purge` leaves the `.swift-sure/` line in the repository's `.git/info/exclude`, which ignores nothing once the
directory is gone. The binary stays, because a running binary does not delete itself; the last
line is the command that removes it: `rm` (of the binary and the `sift` link `install.sh` made beside it), `brew uninstall` or, for an earlier npm install, `npm uninstall`, by how it was installed. Running it again says `uninstall: nothing to do`.

## Configuring a large codebase

Everything works with **no config file at all**; reach for `.swift-sure.json` at the repo root when the
defaults misjudge the repo. Every key, and what it does, is in
`Docs/Guide.md` §9:

```json
{
  "roots": ["Modules/Foo", "Apps/Bar"],
  "exclude": ["Generated/", "Legacy/"],
  "moduleMap": { "Modules/Foo/Sources": "Foo" },
  "indexStorePath": "/path/to/Index.noindex/DataStore"
}
```

On a large monorepo `roots` is the main lever on first-index time. `.swift-sure/` is added to
`.git/info/exclude` automatically on first use, so the cache never needs a committed change.

## What the answers promise

Every answer opens with a header that never claims more than it knows; `swift-sure help answers` gives
the full promise.

- **Syntactic answers** (digests, declarations, member source) are never stale. **Semantic answers**
  (callers, overrides, references) come from the build's index store, and only a *build* refreshes
  that: a symbol whose file changed since the last build is refused with "build the project".
- **One store holding two configurations is the exception, and nothing marks it.** Native debug and
  release builds that pass one `-index-store-path` share a store, and a call the debug build no longer
  makes can still answer `fresh` from the release build's unit. Build the other configuration again, or
  delete the store and build once; the default layouts keep the two apart.
- **Dependencies and SDKs are not indexed**, only repo sources.

## Troubleshooting

**It dies instantly with no output (exit 137).** A new binary was copied over an installed one in
place; see Install. Copy to a temporary name, then rename it over the old binary (new inode).

**"no index store for this tree yet".** The semantic half needs a real build: `swift-sure run -- swift build`
for a SwiftPM package, or `swift-sure run -- xcodebuild -scheme <Scheme> build` for a macOS project (add
`-workspace <W>.xcworkspace` when there is one; a bare `xcodebuild build` with no scheme builds into
`./build/` and is never discovered). An iOS project also needs a destination, or it targets a generic
device and fails to sign: `-destination 'generic/platform=iOS Simulator'`. Then `swift-sure status` reports
which store it found, or names an `indexStorePath` it read and rejected. An `xcodebuild
-derivedDataPath <Pkg>/.build/DerivedData`, where `<Pkg>` is the repo root or a directory holding a
`Package.swift`, is found with nothing to set, and so is a SwiftPM build of a package nested below the
repo root (`swift build --package-path <Pkg> --build-tests`), which leaves its store in `<Pkg>/.build`.
Any other custom `-derivedDataPath` needs `indexStorePath` set in `.swift-sure.json`, pointing at the
store directory itself — the one holding `v<N>/units`, relative to the repo root:
`<path>/Index.noindex/DataStore` for `-derivedDataPath <path>`. The discovery
order is in `Docs/Guide.md` §7.

**MCP server not appearing in Claude Code.** Start a new session first, then check `claude mcp list`.
When registering by hand, `--scope` must come *before* the `--`, or the binary receives it:

```sh
claude mcp remove swift-sure
claude mcp add --transport stdio --scope local swift-sure -- swift-sure mcp   # from the repository's root
```

**Answers look thin right after an upgrade.** An upgrade can change the index's format, as the one that
reads a backticked declaration by its bare word did. An index written by an earlier version is dropped and
rebuilt once, on its repository's next query; until then that repository gives reduced answers. `swift-sure index`
in it rebuilds it up front.

**First index feels slow, or `git status` is the bottleneck.** Narrow `roots` first. If `git
status` itself exceeds ~200ms on your repository, git's `fsmonitor` will not help swift-sure: every git the tool
runs switches the repository's fsmonitor hook off, so a hook named in a repository's config is never started by a
lookup.

**Everything is refused as stale.** The build is older than your edits. That is the contract
working, not a bug.

**`where` says the store is "still warming".** A large store takes minutes to read the first time,
so the query answers with declarations rather than blocking. It is not the staleness refusal: no
build and no reindex will speed it up. The read continues in the background; ask again in a moment.
