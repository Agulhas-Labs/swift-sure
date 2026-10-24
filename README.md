# SwiftSure

[![Release](https://img.shields.io/github/v/release/Agulhas-Labs/swift-sure)](https://github.com/Agulhas-Labs/swift-sure/releases)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
![Platform: macOS 13+, Apple silicon](https://img.shields.io/badge/platform-macOS%2013%2B%20Apple%20silicon-lightgrey)

**What broke, who calls it, and whether anything ran: Swift answers your AI agent can trust.**

SwiftSure (`swift-sure`, also run as `swift sure …`; `sift` stays as an alias for one release) sits beside
Claude Code, Cursor and Codex. Everything runs on your machine.

**It leads with build and test output an agent can afford to read.**

- `swift-sure run -- <command>` wraps `swift build`, `swift test` and `xcodebuild` and prints only what failed, with
  each failure at its file and line; the full log is filed. The Claude Code hooks rewrite a bare build or test into it.
- `swift-sure test` runs a scheme's tests across several simulators, or a package's across several `swift test`
  processes. `swift-sure flakes` counts how often each test has been recorded failing across wrapped runs.
  `swift-sure affected` lists the tests that reference what a diff changed, as `-only-testing:` arguments; it never
  runs or skips anything.
- **Measured:** on 18 build and test outputs, `run` cut the bytes by a median 89%, and located 68 of 68 failures the
  logs held; `tail -50` of the same logs named 42 of them in full ([results](Benchmarks/RESULTS-run-compression.md)).
  That is output size, not an agent's session cost.

The default install adds the index too (symbol lookups, an MCP server, more hooks): [see below](#the-index). `--run-only` installs the build and test side alone.

## The problem

- An agent reads a whole build log to find one failing test, and pays for every line.
- A filtered test run that matched nothing prints "passed", and the agent believes it.

## Before and after

The same failing test in a three-test package. The agent's `swift test` printed 22 lines (the tail is below):

```
✘ Test aFailingTest() recorded an issue at Gizmo.swift:9:5: Expectation failed: depot.count == 2
↳ depot.count == 2 → false
↳   depot.count → 1
✘ Test aFailingTest() failed after 0.001 seconds with 1 issue.
✘ Test run with 3 tests in 0 suites failed after 0.001 seconds with 1 issue.
Note: Some test targets reported failures:
  - Gizmo (Swift Testing)
```

`swift-sure run -- swift test` printed this, and filed the full log:

```
✘ swift test — exit 1
  aFailingTest() — Tests/Gizmo/Gizmo.swift:9 (body :6-10) (not in a changed file)
    Expectation failed: depot.count == 2 → false depot.count → 1
totals: ✘ failed · Swift Testing 3 tests in 0 suites, 1 failing, 0 skipped
inventory: 3 declared, 3 reported
raw: Depot @ 8c1eabf (Swift clean) · .swift-sure/runs/failed-a6fea85e-run-20261022-115723Z-b97033e8.log (21 lines in, 6 out), kept until it passes or 5 newer failures
```

A small package shrinks little; the saving grows with the log ([the measurements](#the-evidence)).

## Builds and tests that tell the truth

`swift-sure run` keeps errors at their file, line and column; a filtered run that ran nothing fails instead of
passing; an unfiltered `swift test` is counted against the tests the index declares (the `inventory:` line above).
The build and test hooks (all that `--run-only` installs) are the `PreToolUse` hook that rewrites a bare build or test into
`swift-sure run --`, the `PostToolUse` hooks that report a build's diagnostics, and the `Stop` gate.

## The index

The default install also registers the lookups. They cost about 1.2k tokens of tool definitions at the start of every
session, and whether that is earned back depends on the work. On nine tasks in a large private app, over paired paths
(216 runs), the index changed a session's cost by a pooled -9.5%: tracing UI text -41%, understanding a large type
-26%, callers across modules -16% and a long open-ended chain -14%; a rename sweep cost 11% more and chained
questions 6% more, and three tasks showed no detectable difference ([results](Benchmarks/RESULTS-live.md)). On short lookups and
fixes in two pinned open-source iOS apps (240 runs each over paired paths) it cost more, +6.1% and +7.0%: one or two
calls do not earn back the fixed start, though tracing UI text still paid (-9% and -10%)
([results](Benchmarks/RESULTS-public-corpora.md)). If you only want the build and test side, install with `--run-only`.

**Answers grep can't give.** `where`, `search`, `strings` and `digest` answer from an index of your
code and, after a build, the compiler's own index store, and every answer says which tree it describes and how
fresh it is. `where` separates real callers from comments and same-named methods; `search` finds code by shape:

```
$ swift-sure search 'kind:func attr:Test calls:Task'
7 declaration(s) in 5 file(s) — scanned 2323 file(s)

Tests/SiftCoreTests/FileScopeScanWidthTests.swift:
  :84-97  FileScopeScanWidthTests.aCancelledScanSaysOneMay() — @Test func aCancelledScanSaysOneMay() async throws
```

(The first of seven matches, from this repository.) Add `!has:await` to ask for the ones that never await.
The server exposes only the query tools (`digest`, `where`, `search`, `strings`); everything else, including
`affected`, stays on the command line.

**Guardrails on every change.** The lookup hooks also check what the agent is about to do. A whole-file `Read` of a big Swift
file (about 12 KB and up in a typical 45k-token context, rising to about 20 KB by 120k; the line moves with the digest's size and the context) comes back as its digest,
and a smaller one is read as asked; an edit that leaves a `.swift` file unparseable comes straight back with its
errors; a bare `swift test` is pointed at `swift-sure run`. Asked by hand what the hook does with that command
in an auto-mode session (`swift-sure pre-tool-use --command 'swift test' --permission-mode auto --verdict`), it prints one line:

```
amended	swift-sure run -- swift test	RunAdvice
```

The hook rules and what Cursor does differently are in [the guide](Docs/Guide.md#cursor-swift-sure-install-hook---agent-cursor-experimental).

## Quick start

```sh
brew install agulhas-labs/tap/swift-sure
swift-sure install      # finds Claude Code, Cursor and Codex, asks once for each; the full set
swift-sure doctor       # proves each agent runs what the install wrote
swift-sure run -- swift build
```

Then start a new agent session. The install is one per machine: the hooks apply in every project for that agent.
For the build and test hooks only (no MCP server, rule, session primer or lookup hooks), `swift-sure install --run-only`;
re-running with or without the flag switches the mode. Needs macOS 13+ on Apple silicon. An agent running the install has no terminal
to answer in, so it names the agent: `swift-sure install --agent claude` (or `cursor` or `codex`, both
experimental). A release bundle and building from source: [INSTALL.md](Distribution/INSTALL.md) and
[the guide](Docs/Guide.md#2-install).

## The evidence

- **Output size.** On 18 build and test outputs from a clone of this repository, green and red, `run` cut the bytes by
  a median 89%; every answer but one was smaller than its log (a no-op `swift build`: 187 B against 175 B), every
  failure the logs held was reported (two crashes by their signal), and none was invented. Deterministic, no model; it
  says nothing about how an agent behaves ([results](Benchmarks/RESULTS-run-compression.md)).
- **Session cost of the index.** Paired benches (one model, six run paths and two repeats per arm per task) found a
  pooled -9.5% on longer work in a large private codebase, whose corpus nobody else can re-run
  ([results](Benchmarks/RESULTS-live.md)), and +6.1% and +7.0% on short lookups and fixes in two public iOS apps, whose
  tasks are in [fieldwork-bench](https://github.com/Agulhas-Labs/fieldwork-bench)
  ([results](Benchmarks/RESULTS-public-corpora.md)). Tasks were picked by the author.
- **Build and test fixes.** On four such tasks in swift-format (a SwiftPM package, no index store) the default install
  cost a pooled 5.3% less [-9.4k, -2.1k], almost all of it from fixing a build error (-34%), where `run`'s answer
  replaced the raw build output ([results](Benchmarks/RESULTS-public-corpora.md)).

The method, the other runs and a rerun recipe are in [Benchmarks/](Benchmarks/README.md).

## Privacy and uninstall

Nothing leaves your machine; there are no network calls. The index is a SQLite file at `.swift-sure/index.db`, kept out
of `git status`. `swift-sure install` copies each settings or rule file it rewrites to `.bak-swift-sure` first, and
`swift-sure uninstall` takes it all back out (`--purge` also deletes every index and log).
[What it touches](Docs/Guide.md#10-what-it-touches) lists every file.

## Read on

- [The guide](Docs/Guide.md): setup, configuration, freshness, every command.
- [The DocC catalog](Docs/SwiftSure.docc/): getting started, the four tools, builds and tests, the hooks.
- [SwiftSure.md](SwiftSure.md): the rule an agent reads. [Docs/Capabilities.md](Docs/Capabilities.md): what it can and cannot do.
- [Docs/Design.md](Docs/Design.md) and [Docs/AnswerContract.md](Docs/AnswerContract.md): how it works, and what every answer promises.
- [CHANGELOG.md](CHANGELOG.md).

## Related

- [simwalk](https://github.com/Agulhas-Labs/simwalk): deterministic UI walks of a running iOS app.
- [Fieldwork](https://github.com/Agulhas-Labs/swift-fieldwork): the shared agent-setup library behind both.

## License

Apache 2.0. See [LICENSE](LICENSE).
