# Paired benchmark: the same tasks with and without SwiftSure

Status: runner and analysis built. Results: `RESULTS.md` (SwiftSure's own repository, 60 runs),
`RESULTS-ios-app.md` and `RESULTS-ios-app-10.md` (a private 148k-line iOS app, 3 and 10 repeats), and
`RESULTS-run-compression.md` (`swift-sure run` output against the raw log, no model), `RESULTS-live.md` (the hook
live, with a compiler index) and `RESULTS-single-call.md` (single-call answers).

## What it measures

Ten fixed Swift-code tasks (`tasks.json`), each run by Claude Code in two arms:

- **Arm A, without SwiftSure**: no SwiftSure hooks, MCP server, rule or binary on `PATH`.
- **Arm B, with SwiftSure**: SwiftSure installed as a user installs it (hooks, MCP server, the `SwiftSure.md` rule).

Three repeats per arm per task on this corpus (60 runs), one model (`claude-sonnet-5-5`). Every run records, from Claude
Code's `stream-json` result:

- input tokens, raw: uncached input, cache writes (split 5-minute and 1-hour), cache reads, summed over
  every model the run used (`modelUsage`);
- session price, the headline: input-token equivalents for one fresh session with no cache carried in from other
  runs. It prices the context series once at the 5-minute write price, re-reads at the read price on later turns,
  and counts output at five times input; a prompt cache that carries over between repeats cannot flatter an arm;
- input tokens, weighted at list-price multiples of the base input price: uncached 1, 5-minute write 1.25,
  1-hour write 2, read 0.1;
- output tokens, turns, wall time, and `total_cost_usd`, which is a list-price equivalent
  (`costBasis: list`), not money billed;
- task success, decided mechanically (below), never by a model.

Reported per task and in total: the paired difference B minus A, median and range over the repeats, and
success counts per arm.

A session at one run path samples one behaviour mode: which tools a model run calls is a near-deterministic
function of the prompt bytes, and the corpus run path is one of those bytes (#799). `--paths K` spreads the
repeats over K run paths (`--repeats` is per path), pairs A with B at the same path, and bootstraps the
interval over paths rather than runs. For a "does this change help" claim use `--paths 6 --repeats 2`, run
from the same checkout as the session it is compared with: the path names are the checkout's, so the same
checkout means the same path set.

## The corpus

SwiftSure's own repository at commit `27d3aca3` (absent from the public repository, whose history starts at the release cut; a rerun passes its own corpus and tasks file with `bench.py run --corpus <repo>@<commit> --tasks <file>`; `Benchmarks/tasks.example.json` is the template), written out with `git archive` into a fresh one-commit
repository for every run, so no history hints at an injected bug. It is about 93k lines of Swift in three
modules, and was private when measured, so the model could not answer from memory.

A public corpus was the first choice and was dropped: the repository's example-name gate
(`ExampleNamesTests`) fails on any camel-cased name that this tree does not declare, and its permit list
forbids names from somebody else's codebase. Task files over SwiftSure's own code pass because the tree
declares every name they use. The cost is a coupling: **renaming a symbol a task names fails SwiftSure's own
suite on `tasks.json`**, and the task must then be re-pinned. A check whose expected answer states a line
number lists it in `pinned_lines` (`file`, `line`, `contains`), and `validate` fails when the corpus's line no
longer holds that text; `validate` names every task missing its controls at once.

## Tasks and success checks

| Kind | Tasks | Check |
| --- | --- | --- |
| find definition | 1 | the `ANSWER:` line holds the path and start line |
| find references / callers | 2 | the `ANSWER:` line's file names equal the expected set exactly (an `ignore` list is neither required nor penalised) |
| understand a type / behaviour | 2 | exact set of names |
| trace UI string | 2 | file and function on the `ANSWER:` line |
| locate and fix | 2 | a one-line bug is injected (exact find/replace, asserted to match once); success is the named test filter passing afterwards with `Tests/` unchanged |
| run tests and report | 1 | a one-line bug is injected; success is the exact set of failing test functions, with no file changed |

Only the last line starting `ANSWER:` is read (Markdown emphasis and backticks stripped). Each test-based
check needs two controls before it counts: green on the clean corpus, red on the injected one. Those
controls were verified at a commit, and so was the expected failing set of the report task (5 functions: 3 of the 6 `ShellWordTests` plus one each in `InstallHookQuotedPathTests` and `UninstallBinaryLineQuotingTests`, over the whole suite); `tasks.json` records each as `verified_at: <commit>`, not a date; the "locate and fix" check for the allow rule is the one test `aTrailingWildcardAlsoMatchesTheBareCommand`, because the broader `RunAllowRules` suites stay green under that injection.

## Isolation

Measured on Claude Code 2.1.286, 1 Oct 2026:

- A scratch `CLAUDE_CONFIG_DIR`, or a scratch `HOME`, logs Claude Code out (`Not logged in`): the login
  credential is not found. Both arms therefore use the real configuration directory, with everything in it
  switched off:
  - `--setting-sources project,local`: no user settings, hooks, permissions or plugins;
  - `--strict-mcp-config --mcp-config <arm file>`: arm A's names no server, arm B's names SwiftSure;
  - `--settings` carrying `claudeMdExcludes` for `~/.claude/**` and for every `CLAUDE.md`,
    `CLAUDE.local.md`, `.claude/CLAUDE.md`, `.claude/rules/**` and `AGENTS.md` in the run directory's
    ancestors (`~/Library/Caches/swift-sure-bench-run/<checkout>`, `~/Library/Caches`, `~/Library`, `~` and up)
    and in the corpus itself (its own agent instructions describe SwiftSure). A probe with these found none of
    the ancestors' `CLAUDE.md` files loaded;
  - `--disable-slash-commands`, `--no-session-persistence`, `--tools Bash,Read,Edit,Write,Grep,Glob`
    (no subagents, so all usage is the run's own), a pinned `--effort`, and `--permission-mode
    bypassPermissions` in both arms: swift-sure's build rewrite reads the mode, and under `dontAsk` it would
    refuse a build once in arm B for a reason the harness made.
- Every run's corpus is at `~/Library/Caches/swift-sure-bench-run/<checkout>/corpus`, where `<checkout>` is the
  first 8 hex digits of the SHA-1 of the checkout's absolute path: one fixed path per checkout, so two
  checkouts can run at once and an index store built at the run path is used from it. The template every
  run is cloned from sits beside it (the rename that makes it and the clone that copies it need one
  volume); the wrapper, scratch home, index store and logs stay in the checkout's `.build/bench`. The
  corpus must not sit under a `.build`, `DerivedData`, `checkouts` or `/tmp` directory: SwiftSure's hook treats
  every path under one as build output and lets every Grep and Read of it through. Until 2026-10-01 it sat
  at `.build/bench/run/corpus`, so arm B ran with its hook inert in every run recorded before then.
- **The hook is checked live before any model call.** Once per session (and in `bench.py validate`), arm B
  is installed in a clone at the run path and its hook, through the wrapper and scratch home, judges one
  whole-file `Read` of the corpus's largest tracked Swift file (`swift-sure replay-hook`). A file whose answer is
  withheld only for its size (rule `overSize`: firefox-ios's 608 KB `Strings.swift`) proves nothing either way, so
  the next largest is tried, up to five. Unless the verdict is
  an answer in place the session halts with exit 3, printing the verdict and rule; otherwise `session.json`
  records `hook_live: true`, the rule (`hook_live_rule`), and the Read's and the answer's characters.
- `run.sh` deletes `.build/bench`, the checkout's cache directory and Claude Code's per-project state for
  the run path when it exits, however it exits (a signal is forwarded to the runner, which stops what it
  started first), and refuses to start while either directory exists.
- `PATH` in both arms has every directory holding a `swift-sure` (or earlier-named `sift`) binary removed; arm B puts a wrapper first. The
  wrapper sets `CFFIXED_USER_HOME` to a scratch home, so SwiftSure's logs, ledgers and roots registry never
  touch the user's `~/.swift-sure`; the hooks and the server read no Claude path from it at run time.
- Arm B installs at project scope inside the corpus: `swift-sure install-hook --settings
  <corpus>/.claude/settings.json --command "<wrapper> session-start"`, and `SwiftSure.md` at
  `<corpus>/.claude/rules/swift-sure.md`. `--command` repoints only the primer, so the runner repoints every
  other hook at the wrapper and refuses to run unless every command is the wrapper's.
- A run is **invalid** (reported, not counted as a failure) unless: in arm A, the init message lists no MCP
  server and no tool naming SwiftSure, no hook event fires, and no Bash command invokes `swift-sure`; in arm B, the
  SwiftSure server is `connected`, its tools are listed and a `SessionStart` hook event fires.
- Arm order alternates by task and repeat, so neither arm always runs first.

## A second corpus (v2)

The runner takes `--tasks <file>` and `--corpus <repository>@<commit>`, so a larger private corpus runs
through the same harness. A tasks file over a private codebase names its symbols, so it lives outside this
repository, is passed by path, and uses generic task ids: the table shows only the ids. Keys a tasks file
may add: `corpus.paths` (the subset to archive), `corpus.warm` (the warm build command, or null for none),
`corpus.add_files` (extra files, such as a build log, copied in from beside the tasks file), `preamble`
(text put before every prompt), and the checks `answer_parts` (` | `-separated answers, scored per part),
`answer_set` with `"match": "path"`, and `restored` (a fix checked without a build: the injection is
reverted, or one of the listed alternatives holds, and no other file changed). `tasks.example.json` shows
every key with placeholder names. Each run's corpus ignores, through `.git/info/exclude`, what arm B's
install and index or an attempted build leave (`.claude/`, `.swift-sure/`, `.build/` and the like), so a "no other
file changed" check cannot fail in arm B alone; `validate` plants that debris in every control.

Each task block now starts with an unscored warm-up per arm (`--max-turns 1`, skipped with `--no-warmup`).
A run's cleanup renames its trees into a trash directory that one background thread empties, and a `tests` check runs in a warm tree kept from the path's previous check, the session's files synced into it so the build is incremental; `--no-reuse` switches both off (today's harness, for a paired comparison), and `--check-both` runs each such check in the session tree as well and prints `CHECK MISMATCH` when the two verdicts differ. Every run records `harness_seconds` (prepare, check, cleanup) beside `wall_seconds`.
Every run records its first-call and peak context (B minus A of the first is SwiftSure's fixed start), and
`session.json` records the SwiftSure binary's sha256 and mtime, the rule file used, chars/4 estimates of the tool
list, primer and rule, and one cold `swift-sure index` time. `bench.py validate --tasks <file>` checks every
task's check against its controls with no model call.

**An indexed corpus.** Without an index store, arm B's `where` answers callers by written name only
(`mode: syntactic`). `corpus.index_build` (a command, run once per session in the corpus at the fixed run
path, since a store records absolute paths) builds one: the command puts Xcode's derived data at the path in
`BENCH_DERIVED_DATA`, which lies beside the corpus, not in it. The harness keeps only the store directory
(`.build/bench/index-store`, about 70 MB for a 148k-line app), deletes the rest of the derived data, and writes
the corpus afresh from the archive, so whatever the build generated in the tree is gone and both arms see the
plain archive; its files carry the commit's time, older than every unit, so the store reads as fresh. No run
copies the store: arm B's install adds a `.swift-sure.json` naming it, which `.git/info/exclude` hides from the "no
other file changed" checks, and arm A's tree has neither the store nor the setting, nor any build product for a
`grep -r` to wade through. SwiftSure never writes to the store (its database goes in the run's own `.swift-sure/`), so
every arm B run starts cold from the same store. For an iOS app the command needs a generic destination,
`xcodebuild … -destination 'generic/platform=iOS Simulator' ARCHS=arm64 build-for-testing`, so no simulator
is created or booted, and `build-for-testing` on each scheme whose tests should be indexed (an app and a local
package are two schemes): a plain `build` leaves the tests out of every caller list. Xcode indexes while
building only an unoptimised build by default, and a scheme's Test configuration can build its packages with
`-O`, so the command also passes `COMPILER_INDEX_STORE_ENABLE=YES`; the harness halts when the build log shows a
Swift module compiled without an index. `session.json` records `corpus_indexed`, `index_store_bytes` and `index_build_seconds`;
`validate` skips the build.

## Threats to validity

- **One model.** Results hold for `claude-sonnet-5-5` on one Claude Code version; another model may use
  the tools differently.
- **Task selection.** The tasks were chosen by SwiftSure's author, on SwiftSure's own code, and most are lookups,
  where SwiftSure is designed to help. The corpus documents SwiftSure, which arm A can read.
- **Repeat variance.** Three repeats give a median and a range, not a confidence interval; a difference
  smaller than the range is not evidence.
- **Cold index.** Arm B indexes the corpus on its first query, and that time is in its wall time.
- **Not a user's session.** Single-prompt `-p` runs with no prior context; a long interactive session
  amortises the fixed cost of SwiftSure's primer and tool list differently.

## Running it

```sh
sh Benchmarks/run.sh --repeats 3                 # every task in tasks.json, both arms
sh Benchmarks/run.sh --task <id> --repeats 1     # one task
sh Benchmarks/run.sh --paths 6 --repeats 2       # 6 run paths x 2 repeats, bootstrapped over paths
sh Benchmarks/run.sh --tasks <file> --corpus <repository>@<commit> --repeats 10
sh Benchmarks/analyse.sh [session]               # the paired table, also written as table.md
python3 Benchmarks/bench.py validate --tasks <file>
python3 Benchmarks/bench.py calls <session> --task <id> --arm B   # each run's tool calls, one per line
python3 Benchmarks/bench.py calls <session>... --split [--task <id>] [--runs]   # the session price split over its parts, per call kind
python3 Benchmarks/bench.py compare <session>... -- <session>... --task <id> --arm B   # one arm across sessions, pooled
python3 Benchmarks/run-compression.py report --out <out>   # see RESULTS-run-compression.md
# ec096ea3 is a commit of the private history, absent from the public repository: save any earlier Sift.md
cp <earlier Sift.md> .build/rule-ec096ea3.md
sh Benchmarks/run.sh --rule-a .build/rule-ec096ea3.md --rule-b SwiftSure.md --repeats 3   # rule vs rule
sh Benchmarks/run.sh --mod-b Distribution/mod --repeats 3   # mod vs no mod
sh Benchmarks/run.sh --no-mcp-b --repeats 3   # arm B: swift-sure without its MCP server
sh Benchmarks/run.sh --plugin-b Distribution/plugin --paths 6 --repeats 2   # plugin route vs installer route
```

`--mod-b <dir>` turns the session into **mod vs no mod**: both arms run with SwiftSure under one rule (`--rule-b`'s),
arm B adds `claude --plugin-dir <dir>`, and arm A runs without it and with `SWIFT_SURE_MOD=off`. Both arms get
`SWIFT_SURE_HOME` in the run's scratch home, so a `mod-off` file in the user's `~/.swift-sure` cannot switch arm B off. Arm B
is valid only if the stream's init event lists the plugin by its `plugin.json` name, arm A only if it does not.
`session.json` records `mod_dir`, `mod_name`, `mod_commit` and `mod_files_sha256` (the files Claude Code writes on
load, `tsconfig.json` and `.claude-plugin/types/`, left out), the table's header names them, and a voluntary-use
table counts SwiftSure calls against Swift Reads and greps per arm. `--mod-b` with `--rule-a` is refused.
Every session's Bash tool runs `/bin/bash` (`session.json`: `bash_tool_shell`), whatever the operator's login shell: zsh's `nomatch` aborted agents' unquoted `--include=*.swift` greps in both arms. A run inherits none of the calling shell's other variables, so a mod switch reaches arm B only through `--mod-env
NAME=VALUE` (repeatable; refused without `--mod-b`), such as `--mod-env SWIFT_SURE_MOD_BASH=on`.
`session.json` records it under `sift_mod_env.B_extra`, and the table's header names it.

`--binary <path>` is the binary under test (`--sift` is still accepted). The harness names what it sets up after the binary's name: the wrapper is `bin/<name>` (with a `sift` alias beside it when the name is not `sift`, as the installer links one), the MCP server and its `mcp__<name>__` tools, the config file and state directory (`.swift-sure.json`, `.swift-sure/`), the environment prefix (`SWIFT_SURE_`) and the rule file. Calls by either name, in either tool prefix, are counted, so sessions recorded under `sift` parse the same.

`--rule-b <file>` is the rule arm B installs (default: the `SwiftSure.md` shipped with `--binary`). `--rule-a <file>`
turns the session into **rule vs rule**: arm A is installed exactly like arm B (hooks, MCP server, wrapper,
index store) but with that rule, and is held to arm B's validity checks. `session.json` then records
`rule_a_file`/`rule_a_sha256` and `rule_b_file`/`rule_b_sha256`, the table's header names both, and B minus A
is rule B's effect against rule A's. Keep the rule file outside `.build/bench/`, which a run deletes.

`--no-mcp-b` measures arm B without SwiftSure's MCP server: hooks, the `SwiftSure.md` rule and the SessionStart primer
stay, arm B's MCP config names no server, and lookups go through the `swift-sure` CLI from Bash (the wrapper is first
on arm B's PATH). Arm B is valid only if the init event lists no MCP server and no SwiftSure tool, plus the usual
SessionStart and no-foreign-hook checks; arm A is unchanged (with `--rule-a` it keeps its server). `session.json`
records `mcp_b: false`, `fixed_overhead_estimates` leaves out `mcp_tools`, and `reparse` reads the flag back.
Refused with `--mod-b`.

`--plugin-b <dir>` measures **the plugin route against the installer route**. Arm A is the installer route exactly
as `--rule-a` installs it (project-scope hooks, `SwiftSure.md` as the rule, an MCP config naming the server, the wrapper
first on `PATH`), held to the sift-on validity checks. Arm B installs nothing in the corpus (no hooks in its
settings, no rule file, an MCP config naming no server) and runs `claude --plugin-dir <dir>` with the wrapper first
on `PATH`, where the plugin's hooks and server find `swift-sure`. Arm B is valid only if the init event lists the plugin
by its `plugin.json` name, its server (`plugin:<name>:<server>`) is `connected` with tools listed
(`mcp__plugin_<name>_<server>__…`) and no other server is listed, a `SessionStart` hook event fires, and a skill
of the plugin is listed; arm A only if it lists no such plugin. Before any model call the plugin's own
`PreToolUse` command from `hooks/hooks.json` runs through the wrapper on one whole-file Read and must answer in
place (recorded as `plugin_hook_*`). Two flags change in this mode, because each hides what arm B measures:
`--disable-slash-commands` (it also removes every skill from the init event) is dropped from **both** arms, and
`--strict-mcp-config` (it hides a plugin's server) is dropped from arm B, which runs with
`ENABLE_CLAUDEAI_MCP_SERVERS=false` so the account's connectors stay out. `session.json` records `plugin_dir`,
`plugin_name`, `plugin_commit`, `plugin_files_sha256`, `slash_commands_disabled: false` and
`strict_mcp_b: false`, and the table's header names the mode. Refused with `--rule-a`, `--mod-b` and `--no-mcp-b`.
