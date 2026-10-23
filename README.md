# SwiftSure

[![Release](https://img.shields.io/github/v/release/Agulhas-Labs/swift-sure)](https://github.com/Agulhas-Labs/swift-sure/releases)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
![Platform: macOS 13+, Apple silicon](https://img.shields.io/badge/platform-macOS%2013%2B%20Apple%20silicon-lightgrey)

**What broke, who calls it, and whether anything ran: Swift answers your AI agent can trust.**

SwiftSure (`swift-sure`, also run as `swift sure …`; `sift` stays as an alias for one release) sits beside
Claude Code, Cursor and Codex and answers for a Swift codebase. Everything runs on your machine.

## The problem

- An agent reads a whole build log to find one failing test, and pays for every line.
- It greps for a method name and gets the comments, the strings and the same name on three other types.
- A filtered test run that matched nothing prints "passed", and the agent believes it.
- A file left unparseable by an edit goes unnoticed until the next build.

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

## Three things it does

**Builds and tests that tell the truth.** `swift-sure run` wraps `swift build`, `swift test` and `xcodebuild`.
Errors keep their file, line and column; a filtered run that ran nothing fails instead of passing; an unfiltered
`swift test` is counted against the tests the index declares (the `inventory:` line above).

**Answers grep can't give.** `where`, `search`, `strings`, `digest` and `affected` answer from an index of your
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

**Guardrails on every change.** Hooks check what the agent is about to do. A whole-file `Read` of a big Swift
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
swift-sure install      # finds Claude Code, Cursor and Codex, asks once for each
swift-sure doctor       # proves each agent runs what the install wrote
swift-sure run -- swift build
```

Then start a new agent session. The install is one per machine: the rule, the user-scope MCP server and the hooks
apply in every project for that agent. Needs macOS 13+ on Apple silicon. An agent running the install has no terminal
to answer in, so it names the agent: `swift-sure install --agent claude` (or `cursor` or `codex`, both
experimental). A release bundle and building from source: [INSTALL.md](Distribution/INSTALL.md) and
[the guide](Docs/Guide.md#2-install).

## The evidence

- **Output size.** On 18 build and test outputs from a clone of this repository, green and red, `run` cut the bytes by
  a median 89%; every answer but one was smaller than its log (a no-op `swift build`: 187 B against 175 B), every
  failure the logs held was reported (two crashes by their signal), and none was invented. Deterministic, no model; it
  says nothing about how an agent behaves ([results](Benchmarks/RESULTS-run-compression.md)).
- **Session cost.** One private codebase, one model, six run paths with two repeats per arm per task, 216 paired runs:
  the pooled session price was 9.5% lower with it (two benchmark batches on separate paths, so the pooled figure has no single
  interval; each session's own interval excludes zero). Four of nine tasks were cheaper, two were dearer
  (chained questions on one type, a rename sweep) and three showed no detectable difference. Tasks were picked by
  the author and nobody else can re-run the corpus ([results](Benchmarks/RESULTS-live.md)).

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
