# What SwiftSure can do

An inventory of every diagnostic, analysis and check SwiftSure has, one section per subcommand, for deciding what exists. The [Guide](Guide.md) is the manual and the [command reference](Guide.md#11-command-reference) is the lookup table; this page is the survey, with a real answer from each command and what it took.

The sections are built from the parser's own command tree: a test fails when a subcommand has no section here, a section names a command that no longer exists, or a section's Flags line leaves out an option `--help` shows. The entry points the agent hooks run (`stop`, `session-start`, `pre-tool-use`, `post-tool-use`) and the two hidden audit helpers (`replay-hook`, `scan-dump`) have no section; the hooks are under [Hook checks](#hook-checks).

Measured on an Apple M4 Max Mac, macOS 27.0.1, on 20 October 2026 with a release build. Answers come from the small sample package `Distribution/docs-fixture.sh` writes (a module called `Stacks`, 5 Swift files), which the DocC articles also use, so a time is a floor for a repository of that size, not a forecast for a large one. `audit` and `report` read this machine's transcripts, so their times say what a week of real use costs. The build and test runs use SwiftPM and the `ValidationProjects/TestDemo` sample app on an iOS simulator that was already booted. Samples are trimmed to fit and have paths shortened to `~`.

## Answers about the code

Index lookups that answer from the parsed tree, with an explicit freshness line on each answer.

### `swift-sure digest`

- **Does:** Prints the declaration surface of a type, file, module or `Type.member` with member line ranges, one member's source, or a Markdown file's heading outline.
- **Flags:** `--all` include private symbols in a module digest; `--signatures-only` drop doc summaries and attributes (a member returns its signature); `--signaturesOnly` the same flag, camel-case spelling; `--offset` skip this many member lines (pagination); `--at` answer as of a commit, branch or tag, by a syntactic parse of that revision; `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.15 s on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  head: ec26cde  clean
  Library — Stacks — Sources/Stacks/Library.swift:3-69
  public final class Library

  stored properties:
    public private(set) var loans: [Loan] = []  :4
    private var shelf = Shelf()  :5
    private let limit: Int  :6

  members:
    public init(limit: Int = 3)  :8-10
    public func stock(_ book: Book)  :12-14
  ```

- **Mentioned in:** Guide §4, §6, §10, §11, MCP tool description, DocC (GettingStarted, HowTheHooksBehave, TheFourTools).

### `swift-sure where`

- **Does:** Resolves a symbol to its declarations, extensions, conformers, overrides and callers, and for a type what uses it; `--refs` lists every reference site for a rename or delete sweep.
- **Flags:** `--syntactic` skip the index store: no callers or overrides; `--refs` every reference site, for rename and delete sweeps; `--files` with refs: only the files the sweep names, with counts; `--decl` only where it is declared; `--offset` skip this many files of the references listing; `--at` answer as of a commit, branch or tag; `--root` repository root.
- **Needs a build:** a compiler index store sharpens it.
- **Typical time:** 0.3 s syntactic, 1.0 s for the first call that opens a built store, on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  head: ec26cde  clean  semantic: fresh

  declarations (1):
    Stacks.Library.lend(title:to:days:) — func — public func lend(title: String, to borrower: String, days: Int) -> Loan? — Sources/Stacks/Library.swif…

  callers of Stacks.Library.lend(title:to:days:) (3):
    Tests/StacksTests/LibraryTests.swift (3):
      :15  lendingMovesABookToLoans()  | let loan = library.lend(title: "Tides", to: "Cleo", days: 7)
      :23  givingBackRestocks()  | _ = library.lend(title: "Atlas", to: "Cleo", days: 7)
      :31  overdueCountsLongLoans()  | _ = library.lend(title: "Tides", to: "Cleo", days: 30)
  ```

- **Mentioned in:** Guide §4, §11, MCP tool description, DocC (GettingStarted, TheFourTools).

### `swift-sure search`

- **Does:** Finds Swift declarations by structural shape (kind, attribute, name, calls, inheritance, modifiers, effects) rather than by text.
- **Flags:** `--offset` skip this many matches (pagination); `--count` the header and summary only, with a per-module breakdown; `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.09 s on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  source: live
  2 declaration(s) in 2 file(s) — scanned 5 file(s)

  Sources/Stacks/Library.swift:
    :16-27  Library.lend(title:to:days:) — public func lend(title: String, to borrower: String, days: Int) -> Loan?

  Tests/StacksTests/LibraryTests.swift:
  ```

- **Mentioned in:** README, Guide §4, §8, §11, MCP tool description, DocC (TheFourTools).

### `swift-sure similar`

- **Does:** Ranks the declarations whose syntactic shape is closest to one you name, to find code to reuse before writing more.
- **Flags:** `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.1 s on the docs fixture.
- **Sample:**

  ```
  similar Library.lend(title:to:days:) — Sources/Stacks/Library.swift:16-27
  no declaration reached 0.35 shared-callee overlap or better (rarity-weighted; the score also weighs control flow and written types) — of 23 with a bo…
  syntactic shape match on written names over the working tree — never stale; a hit is a lead to confirm with digest Type.member, and the list is a low…
  ```

- **Mentioned in:** Guide §4, §11, SwiftSure.md.

### `swift-sure dupes`

- **Does:** Groups declarations whose bodies are near-duplicates, across the tree or under a path.
- **Flags:** `--min` the shared-callee overlap, 0 to 1, a pair must reach (default 0.50); `--offset` skip this many groups (pagination); `--tests` rank test and preview code too; `--no-tests` leave test and preview code out (with neither, it is ranked after the rest); `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.2 s on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  source: live
  dupes .
  no pair of declarations reached 0.50 shared-callee overlap or better (rarity-weighted; the score also weighs control flow and written types), sharing…
  ```

- **Mentioned in:** Guide §4, §11.

### `swift-sure strings`

- **Does:** Traces display text to its localization key (or a key to its text) across string catalogs, and to the Swift literals that hold it.
- **Flags:** `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.1 s on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  source: live
  no string catalogs (.xcstrings / .strings) in this repo
  no Swift string literal contains it either
  ```

- **Mentioned in:** Guide §4, §11, MCP tool description, DocC (TheFourTools).

### `swift-sure affected`

- **Does:** Lists the tests that reference the symbols a diff changed, with the `-only-testing:` arguments; it reports and never runs or skips anything.
- **Flags:** `--from` read the change set from this commit instead of the working tree; `--to` the far end of the `--from` range (default HEAD); `--depth` reference hops to follow from the changed declarations; `--reached` say whether one named test or suite was reached, and at what depth; `--suites` list every affected suite even when the list is long; `--root` repository root.
- **Needs a build:** a compiler index store sharpens it.
- **Typical time:** 0.1 s clean, 0.3 s with an edit, on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  head: ec26cde  dirty: 1  parse_errors: 0  semantic: stale since last build (1 cited file changed: Sources/Stacks/Library.swift)
  affected tests — changed: working tree vs HEAD
  mode: syntactic + semantic (index store via .build)
  depth: 2 reference hops from the changed declarations
  changed files (1), declarations resolved (15):
    Sources/Stacks/Library.swift — added or modified, 15 declarations
  affected tests (3 in 1 target) — swift test commands only (the index store is .build):
    StacksTests — 3 tests
      StacksTests.LibraryTests/givingBackRestocks() — 1 hop, name match — Tests/StacksTests/LibraryTests.swift:20
      StacksTests.LibraryTests/lendingMovesABookToLoans() — 1 hop, name match — Tests/StacksTests/LibraryTests.swift:12
      StacksTests.LibraryTests/overdueCountsLongLoans() — 1 hop, name match — Tests/StacksTests/LibraryTests.swift:28
  ```

- **Mentioned in:** README, Guide §4, §6, §11, SwiftSure.md, DocC (RunningBuildsAndTests).

### `swift-sure diff`

- **Does:** Summarises which declarations a git range added, removed or changed, who calls the changed signatures and which tests reach the changed files, in place of the raw diff. An `access:` section names the declarations the range put at `open`, `public` or `package` that nothing outside their module uses.
- **Flags:** `--member` show one changed declaration's before and after body; `--offset` skip this many declaration entries (pagination); `--coverage` add the coverage the last `run --coverage` recorded; `--root` repository root.
- **Needs a build:** a compiler index store sharpens it.
- **Typical time:** 0.4 s on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  head: ec26cde  dirty: 1  parse_errors: 0  semantic: stale since last build (1 cited file changed: Sources/Stacks/Library.swift)
  diff: working tree vs HEAD — staged, unstaged and untracked changes
  1 file changed — 1 Swift file broken down below (declarations: 0 removed, 1 changed, 0 added)

  Sources/Stacks/Library.swift (modified, +4/-2):
    Library:
      ~ func lend(title:to:days:)  :16-27 (body changed; signature unchanged)
    outside declarations:
      + comments or doc comments  :71
  tests reaching the changed files (3 tests in 1 target) — from `swift-sure affected`: the declarations the diff touched in each changed file (every declarat…
    StacksTests.LibraryTests/givingBackRestocks() — 1 hop, name match — Tests/StacksTests/LibraryTests.swift:20
  ```

- **Mentioned in:** README, Guide §4, §11, §12.

### `swift-sure checkup`

- **Does:** Lists what a change left unproved and what still leans on it, in one answer and one fixed order, over the change `diff` reads: each finding ends in the command that shows its detail, and every check is named as checked or not checked, with its reason. It builds nothing and runs nothing; whether the change was tested is what `run` recorded.
- **Flags:** `--offset` skip this many finding lines (pagination); `--root` repository root. The range is `diff`'s: a commit, `A..B`, `A...B`, or omitted for the working tree against `HEAD`.
- **Needs a build:** no.
- **Typical time:** under a second on the docs fixture.
- **Sample:**

  ```
  tree: app  head: 3f2a9c1  clean  semantic: fresh
  checkup: main...HEAD — HEAD against its merge-base with main, 81c0d2e · 3 findings over 4 changed files — 1 callers, 1 unproved, 1 duplicate
  checked: callers (store open; 1 name-matched), test runs (recorded), exposure, flaky tests (over 9 runs), duplicates · not checked: changed-line coverage (none recorded on this content in this checkout — swift-sure run --coverage --from 81c0d2e -- swift test)
  callers    Sources/App/Gizmo.swift:41  Gizmo.spin(speed:) removed; 3 callers on lines this change did not edit, first Sources/App/Rig.swift:88 (name-matched) — swift-sure diff
  unproved   no unnarrowed test run is proved green on this content (last green: swift test --filter GizmoTests, narrowed, 4m ago); 12 tests reach the change — swift-sure run -- swift test
  duplicate  Sources/App/Gizmo.swift:60-88  Gizmo.wobble() and Widget.wobble() at Sources/App/Widget.swift:12-40 clear both gates (0.72) — swift-sure similar Gizmo.wobble
  ```

- **Mentioned in:** Guide §11.

## Builds and tests

Commands that run the toolchain and report what happened.

### `swift-sure run`

- **Does:** Runs a Swift toolchain command (`swift build`, `swift test`, `xcodebuild`, `swiftlint`) and prints only what failed, with the whole log kept; its modes prove a test fails without a change, answer from a recorded pass, or report coverage of the changed lines.
- **Flags:** `--without` set aside the uncommitted changes under a pathspec, run, put back, run again; `--without-line` comment out one line, run, put back, run again; `--since` with `--without`: set aside what commits since a revision changed; `--guard` with `--without` or `--without-line`: a test expected to pass both ways; `--keep-without-build` keep the build the run without the change made; `--restore` put back changes a `--without` run never restored; `--proved` answer whether this command already passed on this exact tree, running nothing; `--require-inventory` exit 6 when a test run that exited 0 has an inventory that is not clean; `--coverage` run with coverage on and say which changed lines the tests reached; `--from` with `--coverage`: the revision the change is measured from; `--root` run as if started in this directory.
- **Needs a build:** it runs the build or tests itself.
- **Typical time:** The docs fixture: `swift build --build-tests` 23 s, `swift test` 4.7 s, `--proved` 0.4 s, `--coverage` 7.4 s, `--without` (two builds and runs) 18.9 s. `xcodebuild test` of one ValidationProjects/TestDemo bundle on an already-booted simulator, 14.6 s.
- **Sample:**

  ```
  ✘ swift test — exit 1
  2 failures · 2 signatures · 1 file · 2 in changed files (matched by name)
    overdueCountsLongLoans() — Tests/StacksTests/LibraryTests.swift:32 (body :28-33)
      Expectation failed: library.overdue(after: 14).count == 2 → false library.overdue(after: 14).count → 1
    lendingMovesABookToLoans() — Tests/StacksTests/LibraryTests.swift:17 (body :12-18)
      Expectation failed: library.available == 2 → false library.available → 1
  totals: ✘ failed · Swift Testing 3 tests in 1 suite, 2 failing, 0 skipped
  inventory: 3 declared, 3 reported
  raw: Stacks @ ec26cde (Swift dirty: 1) · .swift-sure/runs/failed-70f3c10f-run-20261020-205216Z-729769a4.log (33 lines in, 9 out), kept until it passes or 5…
  ```

- **Mentioned in:** README, Guide intro, §4, §5, §9, §10, §11, §12, SwiftSure.md, DocC (GettingStarted, HowTheHooksBehave, RunningBuildsAndTests, SwiftSure, TheFourTools, Troubleshooting).

### `swift-sure build`

- **Does:** Builds a SwiftPM package clean with the compiler's timers on and ranks the slowest bodies, expressions and files to type-check.
- **Flags:** `--analyse` the only mode: build clean and rank by type-check time; `--build-tests` build the test targets too so their code is ranked; `--top` how many bodies, expressions and files to list (default 10); `--root` repository root.
- **Needs a build:** it runs the build or tests itself.
- **Typical time:** 9.2 s on the docs fixture.
- **Sample:**

  ```
  ✔ swift-sure build --analyse — clean build, 9.1s, 108 timing lines over 4 files
  slowest bodies — 3 of 30 sites:
    Sources/Stacks/Shelf.swift:12 · 18.75 ms · Shelf.take(title:)
    Sources/Stacks/Library.swift:16 · 9.35 ms · Library.lend(title:to:days:)
    Sources/Stacks/Library.swift:29 · 8.65 ms · Library.giveBack(title:)
  slowest expressions — 3 of 54 sites:
    Sources/Stacks/Book.swift:16 · 8.13 ms · Book.titleStarts(with:)
    Sources/Stacks/Shelf.swift:13 · 6.67 ms · Shelf.take(title:)
    Sources/Stacks/Library.swift:39 · 5.55 ms · Library.count(for:)
  ```

- **Mentioned in:** README, Guide §4, §11, §12, SwiftSure.md.

### `swift-sure test`

- **Does:** Splits a scheme's tests across simulators it creates, or a SwiftPM package's across `swift test` processes, and reconciles what ran against the declared inventory; `--analyse` counts what is supposed to run without running anything.
- **Flags:** `--analyse` count the tests that are supposed to run, from the index and the plans; `--sweep` delete simulators this checkout's runs left behind, run nothing; `--scheme` the scheme to build and run; `--device` the device type to create simulators of; `--os` the runtime version to create them on; `--plan` the test plan to run; `--against` reconcile a finished run's output against the declared inventory; `--only` run only this Target, Class or test (repeatable); `--skip` leave out this Target, Class or test (repeatable); `--shards` how many simulators or processes to split across; `--shard-timeout` floor under a shard's time bound, in seconds; `--stock` boot shards stock, with no simulator services switched off; `--animations` leave animations on in the app under UI test; `--project` the `.xcodeproj` the scheme lives in; `--workspace` the `.xcworkspace` the scheme lives in; `--root` repository root.
- **Needs a build:** it runs the build or tests itself (`--analyse` and `--sweep` build nothing).
- **Typical time:** 5.1 s sharded on the docs fixture; `--analyse` 1.1 s over ValidationProjects. Not measured here: a scheme run was not timed.
- **Sample:**

  ```
  ✔ swift-sure test — 3 tests passed across 1 shard
    expected 3 · ran 3 · passed 3 · failed 0 · skipped 0 · missing 0 · duplicated 0
    shards: 1 — 3 tests, wall 1.2s (predicted 3s)
  ⚠ swift-sure test --analyse — 8504 declared · 38 in a plan · 36 run · 2 never run · 0 conditional — 6 targets, 3 plans
    runs 36 = 38 in a plan − 2 never runs − 0 conditional
    in a plan 38 = 8504 declared − 8466 outside every plan's container − 0 no plan under consideration admits

  target             declared  in a plan  runs  never runs  conditional
    Demo Spaced Tests       2          2     2           0            0
    DemoLogicTests          8          8     8           0            0
    DemoUITests            12         12    12           0            0
    DemoUnitTests          16         16    14           2            0
  ```

- **Mentioned in:** README, Guide §4, §10, §11, §12, SwiftSure.md, DocC (RunningBuildsAndTests).

## Setup and health of the index

### `swift-sure init`

- **Does:** Inspects the repository layout and proposes a `.swift-sure.json` (module resolution, indexed roots), writing it only when asked.
- **Flags:** `--write` write `.swift-sure.json` instead of only printing the proposal; `--force` merge into an existing `.swift-sure.json`, keeping its values; `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.6 s on the 5-file docs fixture.
- **Sample:**

  ```
  scanned 5 Swift source file(s) (+1 build manifest(s))

  modules resolved from build files: 2 covering 5 file(s)
    Stacks (4)  StacksTests (1)

  every file's module comes from a build file — no moduleMap needed

  roots: every top-level directory holds Swift — left empty (index the whole repo)
  ```

- **Mentioned in:** Guide §9, §10, §11, DocC (GettingStarted).

### `swift-sure index`

- **Does:** Builds or incrementally refreshes the repository index that every lookup reads.
- **Flags:** `--full` rebuild from scratch instead of refreshing; `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.5 s on the docs fixture (first build, 5 files); `--full` 0.3 s.
- **Sample:**

  ```
  tree: Stacks  head: ec26cde  clean  semantic: syntactic-only
  index up to date
  ```

- **Mentioned in:** Guide §2, §5, §6, §11, DocC (Troubleshooting).

### `swift-sure status`

- **Does:** Reports index freshness and contents, the index store it found, config, and agent definitions that cannot reach the tools.
- **Flags:** `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.2 s on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  head: ec26cde  clean  semantic: fresh
  root: ~/Stacks
  files: 5  symbols: 38  db: 0.1 MB
  modules (2): Stacks StacksTests
  config: none (defaults)
  index store: .build — ~/Stacks/.build/out
  ```

- **Mentioned in:** Guide §2, §4, §5, §6, §10, §11, DocC (GettingStarted, HowTheHooksBehave, Installing, Troubleshooting).

### `swift-sure help`

- **Does:** Prints the reference topics behind the short rule (run output, answers, queries, refusals, test output, worktree index, build output, affected limits), or a subcommand's usage.
- **Flags:** none beyond `--help`; takes a topic or subcommand name as its argument.
- **Needs a build:** no.
- **Typical time:** 0.02 s.
- **Sample:**

  ```
  Topics:
    run-output — Reading a red `swift-sure run` block — bulk failures, per-example locations, wide builds — and what `swift-sure flakes` counts.
    answers — What every index answer promises: the parse-error banners, semantic staleness, and how root resolution picks a repository.
    queries — The depth behind `digest`, `where`, `search`, `strings` and `affected` — boundary cases, query syntax, and how to read a lower bound.
    refusals — The hook's own accounting — what counts as a lookup, what doesn't, when it goes quiet, and which build commands it never nudges.
    test-output — Reading `swift-sure test`'s answer line by line — the verdict, the counts, a missing or duplicated test, the per-shard line, and what feeds…
    worktree-index — Why `where` and `affected` answer thin in a linked worktree, why the checkout it was cut from is not read in its place, and how to…
  ```

- **Mentioned in:** Guide §4, §7, §11, SwiftSure.md, DocC (GettingStarted, TheFourTools, Troubleshooting).

### `swift-sure reconcile`

- **Does:** Diffs the index against the working tree and fixes every divergence.
- **Flags:** `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.2 s on the docs fixture.
- **Sample:**

  ```
  tree: Stacks  head: ec26cde  clean  semantic: syntactic-only
  reconcile: removed 0, reindexed 0
  ```

- **Mentioned in:** Guide §6, §11, DocC (Troubleshooting).

### `swift-sure reset`

- **Does:** Deletes `.swift-sure/` entirely: the index (rebuilt by the next query), the logs of past runs, and a linked worktree's `swift-sure test` build.
- **Flags:** `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.05 s on the docs fixture.
- **Sample:**

  ```
  removed .swift-sure/ — the next query rebuilds it; kept ~/Stacks/.git/swift-sure/proved-runs.json: the proved-run ledger every worktree of this repository shares…
  ```

- **Mentioned in:** Guide §4, §5, §10, §11, §12, DocC (Troubleshooting).

## Measuring use

Reports built from the usage log, the run log and the agents' transcripts.

### `swift-sure usage`

- **Does:** Summarises the index usage log: calls by tool, root and day, latency, top targets.
- **Flags:** `--file` usage log to read; `--run-file` wrapped-run log to read; `--since` only calls on or after this day; `--root` only calls under this directory; `--unredact` print the real target, root and failure names; `--all-roots` print every root, not the top 5; `--include-scratch` count scratch roots too.
- **Needs a build:** no.
- **Typical time:** 0.03 s over this run's small log.
- **Sample:**

  ```
  usage — 0 failures, 9 calls, 2026-10-20 → 2026-10-20, from 1 session
  log: ~/.swift-sure/usage.jsonl
  counted: one call per answer swift-sure logged, failures and Markdown outlines included; swift-sure audit counts the transcripts' Swift lookups by any route inst…

  by tool:
    digest       3   p50 —     p90 —
    where        3   p50 —     p90 —
    search       2   p50 —     p90 —
    strings      1   p50 —     p90 —
    answered elsewhere: 9 on the CLI — counted above, left out of p50/p90, since their time includes opening the index

  by root:
  ```

- **Mentioned in:** Guide §11, §12, DocC (Installing).

### `swift-sure flakes`

- **Does:** Counts how often each test has been recorded failing across wrapped runs, and separates a failure on identical bytes from one that follows a change.
- **Flags:** `--file` wrapped-run log to read; `--since` only runs on or after this day; `--root` only runs under this directory and its worktrees; `--unredact` print the real test and root names.
- **Needs a build:** no.
- **Typical time:** 0.2 s over a log of five runs.
- **Sample:**

  ```
  2 tests have both failed and passed (in repo-6377f2 — the repository this was run in; --root / for every repository), over 5 runs that recorded which…

  same tree — failed and passed on identical bytes under one command line, over 4 runs that recorded their tree:
    no test both failed and passed on one tree

  failed only on trees, or under command lines, it never passed on:
  swift test — 4 runs:
       2 of 4   last 2026-10-20   test-f5077e
       2 of 4   last 2026-10-20   test-910c60
  ```

- **Mentioned in:** Guide §11.

### `swift-sure audit`

- **Does:** Audits Claude Code transcripts for Swift lookups the index could have served but did not, and replays them against the advice hook as it stands now.
- **Flags:** `--since` only lookups on or after this day (default 7d); `--until` only lookups before this day; `--all` every transcript regardless of age; `--transcript` audit one transcript and its subagents; `--projects` transcript directory to scan; `--root` only transcripts recorded under this directory; `--unredact` print real file, project, symbol and root names; `--replay` put a sample of calls to the advice hook as it stands now; `--shapes` with `--replay`: every shape of every still-cold rule; `--against` compare against another SwiftSure binary's scan or replay; `--scan-diff` with `--against`: diff this build's scan with the other binary's; `--all-windows` with `--scan-diff`: list every window that moved class; `--summary` only the summary, without the worst-transcripts list; `--share` only the headline and voluntary share; `--by` the summary as a trend, one line per day or period; `--sample` with `--replay`: how many contexts to replay; `--progress` print the scan's advance; `--verbs` what SwiftSure's own answers cost, one row per kind of answer; `--include-scratch` count scratch roots too.
- **Needs a build:** no.
- **Typical time:** 111 s over seven days of this machine's transcripts (`--share`); it scales with the transcripts, not the repository.
- **Sample:**

  ```
  served by swift-sure — 36% = 2478 / 6932 of the lookups that had a choice
  voluntary — 33% = (2478 indexed − 221 answered) / (2478 indexed + 4408 cold) of the lookups that had a choice
  28 sessions against scratch roots (temporary, cache or .build directories) not counted
  ```

- **Mentioned in:** README, Guide §4, §10, §11, SwiftSure.md, DocC (HowTheHooksBehave, Installing).

### `swift-sure report`

- **Does:** Writes a self-contained HTML page of conditions, index share, estimated savings and failures, and opens it.
- **Flags:** `--since` window (default 7d); `--root` only calls and transcripts under this directory; `--out` where to write the page; `--file` usage log to read; `--run-file` wrapped-run log to read; `--projects` transcript directory to scan; `--include-scratch` count scratch roots too; `--no-open` write the page without opening it; `--progress` print each stage on stderr; `--deploys` list each install of the binary instead of the page.
- **Needs a build:** no.
- **Typical time:** 120 s over seven days of this machine's transcripts, `--no-open`; it scales with the transcripts.
- **Sample:**

  ```
  ~/.swift-sure/report.html
  ```

- **Mentioned in:** Guide §10, §11, DocC (HowTheHooksBehave).

## Agent setup and servers

Installing SwiftSure into an agent, checking it, and the server it runs.

### `swift-sure mcp`

- **Does:** Runs the MCP stdio server that offers `digest`, `where`, `search` and `strings` to an agent.
- **Flags:** `--root` repository root.
- **Needs a build:** no.
- **Typical time:** 0.15 s from start to a `tools/list` answer.
- **Sample:**

  ```
  {"id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"version":"0.2.1","name":"swift-sure"}},"jsonrpc":"2.0"}
  ```

- **Mentioned in:** Guide §3, §4, §11, DocC (Installing, Troubleshooting).

### `swift-sure servers`

- **Does:** Lists the MCP servers this machine believes are running and stops ones you name.
- **Flags:** `--stop` stop the servers named by `--pid` and `--root`; `--pid` a server to stop, by process id (repeatable); `--root` stop the servers serving this directory; `--yes` actually send the signal (without it, print the plan); `--file` server lifecycle log to read; `--usage-file` usage log to read for signs of life.
- **Needs a build:** no.
- **Typical time:** 0.02 s.
- **Sample:**

  ```
  mcp servers — none this machine believes are running
  ```

- **Mentioned in:** Guide §4, §11.

### `swift-sure install`

- **Does:** Sets SwiftSure up in every agent found on the machine (Claude Code, Cursor, Codex), asking once per agent; idempotent.
- **Flags:** `--agent` install into this agent whether or not it was found (repeatable); `--all` install into all three agents; `--yes` install into every agent found without asking; `--dry-run` say what would be written, write nothing; `--allow-run` Claude Code: add both blocks of allow rules without asking; `--allow-lookups` Claude Code: add only the lookup allow rules; `--cursor-dir` the directory holding Cursor's `mcp.json` and `hooks.json`; `--codex-dir` the Codex home to install into.
- **Needs a build:** no.
- **Typical time:** 0.1 s for `--dry-run`.
- **Sample:**

  ```
  Claude Code: found — `claude` on PATH
      would write ~/.claude/settings.json (hooks)
      would write ~/.claude.json (the MCP server at user scope, through `claude mcp add`)
      left as installed ~/.claude/rules/swift-sure.md (the agent rule) — no SwiftSure.md ships beside this binary to refresh it from (install.sh writes it; `swift-sure …
  Cursor: found — ~/.cursor exists
      would write ~/.cursor/mcp.json (the MCP server)
      would write ~/.cursor/hooks.json (hooks)
  Codex: found — `codex` on PATH
  ```

- **Mentioned in:** README, Guide §2, §4, §10, §11, DocC (GettingStarted, HowTheHooksBehave, Installing, SwiftSure, Troubleshooting).

### `swift-sure doctor`

- **Does:** Checks that each agent SwiftSure is installed into really runs it: registration, binary, hooks (each is executed), MCP server and version.
- **Flags:** `--agent` check only this agent (repeatable); `--cursor-dir` the directory holding Cursor's config; `--json` print the answer as one JSON object; `--codex-dir` the Codex home to check.
- **Needs a build:** no.
- **Typical time:** 0.4 s for Claude Code on this machine.
- **Sample:**

  ```
  doctor: passed — 0 of 12 checks failed
  claude hooks: pass — registered for SessionStart, SubagentStart, PreToolUse, PostToolUse, PostToolUseFailure, Stop, SubagentStop
  claude server: pass — swift-sure — ~/.local/bin/swift-sure mcp
  claude binary: pass — ~/.local/bin/swift-sure runs
  claude version: pass — registered 0.2.1, running 0.2.1
  claude hook SessionStart: pass — exit 0, silent
  claude hook SubagentStart: pass — exit 0, silent
  ```

- **Mentioned in:** README, Guide §2, §10, §11, DocC (Troubleshooting).

### `swift-sure install-hook`

- **Does:** Registers the session primer, the PreToolUse advice hook, the PostToolUse nudge and the Stop build check with an agent; idempotent.
- **Flags:** `--settings` settings file to edit; `--command` the primer's command, spelled `<path>/swift-sure session-start` (the other hooks keep this binary's path); `--allow-run` add the allow rules for lookups and builds without asking; `--no-allow-run` add neither block of allow rules; `--allow-lookups` add only the lookup allow rules; `--agent` claude (default), cursor or codex; `--cursor-dir` with Cursor: the directory holding its config; `--codex-dir` with Codex: the Codex home.
- **Needs a build:** no.
- **Typical time:** 0.06 s against a scratch settings file.
- **Sample:**

  ```
  hook: registered for SessionStart (startup, resume, clear, compact) and SubagentStart — /usr/local/bin/swift-sure session-start
        registered for PreToolUse (Bash|Read|Grep|Glob|mcp__xcode__Xcode(Read|Grep|Glob)|mcp__swift-sure__.*|Write|Edit|MultiEdit) — /usr/local/bin/swift-sure pre-…
        registered for PostToolUse (Write|Edit|MultiEdit|mcp__swift-sure__digest|Grep|Bash) — /usr/local/bin/swift-sure post-tool-use
        registered for PostToolUseFailure (Bash) — /usr/local/bin/swift-sure post-tool-use
        registered for Stop and SubagentStop — /usr/local/bin/swift-sure stop
  permissions: nothing added
  ```

- **Mentioned in:** Guide §3, §4, §10, §11.

### `swift-sure uninstall-hook`

- **Does:** Removes the hooks SwiftSure registered, leaving anything it did not register alone; idempotent.
- **Flags:** `--settings` settings file to edit; `--only-advice` remove only the PreToolUse advice hook; `--agent` claude (default), cursor or codex; `--cursor-dir` with Cursor: the directory holding its config; `--codex-dir` with Codex: the Codex home.
- **Needs a build:** no.
- **Typical time:** 0.01 s against a scratch settings file.
- **Sample:**

  ```
  hook: removed SessionStart — /usr/local/bin/swift-sure session-start
  hook: removed SubagentStart — /usr/local/bin/swift-sure session-start
  hook: removed PreToolUse — /usr/local/bin/swift-sure pre-tool-use
  hook: removed PostToolUse — /usr/local/bin/swift-sure post-tool-use
  ```

- **Mentioned in:** Guide §4, §11, DocC (HowTheHooksBehave, Installing).

### `swift-sure uninstall`

- **Does:** Removes SwiftSure from Claude Code, Cursor and Codex (hooks, MCP server, rule) and lists the `.swift-sure/` directories it left; idempotent.
- **Flags:** `--settings` settings file to edit; `--purge` also delete every listed `.swift-sure/` directory and `~/.swift-sure`.
- **Needs a build:** no.
- **Typical time:** 0.02 s, against an empty home (nothing to remove).
- **Sample:**

  ```
  uninstall: nothing to do
        `swift-sure uninstall --purge` deletes them: the indexes rebuild on the next query; the usage and run logs are gone for good
  the band step was skipped: --settings names a file other than the user's settings, which is what `claude plugin` edits
  ```

- **Mentioned in:** README, Guide §4, §11, DocC (HowTheHooksBehave, Installing).

## Hook checks

What SwiftSure registers with an agent, one row per event, and what the check does. Claude Code gets all of them; Cursor gets the session, pre, post and post-failure events; Codex gets session, pre and post. The checks are described in the [Guide](Guide.md#4-teach-the-agent-to-actually-use-it); `swift-sure doctor` runs each registered hook to prove it answers.

| Event | Runs | What it checks |
| --- | --- | --- |
| SessionStart, SubagentStart (Cursor `sessionStart`, Codex `SessionStart`) | `session-start` | Prints the session primer: which lookup answers what, and whether this directory has an index. Silent outside Swift work. The subagent copy adds a line for its case. |
| PreToolUse (Cursor `preToolUse`, Codex `PreToolUse`) | `pre-tool-use` | Judges a shell, Read, Grep or Glob lookup of Swift source and refuses it with the index call that answers it (the identical re-run is allowed); rewrites a raw `swift build`, `swift test` or `xcodebuild` to its `swift-sure run --` wrapping where no permission prompt can follow; backs off after a run of denials. |
| PostToolUse (Cursor `postToolUse`, Codex `PostToolUse`) | `post-tool-use` | After a Write, Edit or MultiEdit of a `.swift` file (Codex: `apply_patch`), parses it and blocks with the errors if the edit left it unparseable; names a function shaped like one that already exists; reads a failed build's output. |
| PostToolUseFailure (Cursor `postToolUseFailure`) | `post-tool-use` | The same reading for a Bash call that exited non-zero: compiler error locations are located as for a success, nothing else of the PostToolUse hook runs. |
| Stop, SubagentStop | `stop` | When a context edited Swift since its last green `swift-sure run` build or test of that tree, blocks the stop once with the build to run. |

## Gaps

None known. Left out on purpose: the hook entry points (`stop`, `session-start`, `post-tool-use`) and the hidden helpers behind `audit --replay --against` and `--scan-diff` (`replay-hook`, `scan-dump`); `pre-tool-use` is under [Putting a question to the hook by hand](Guide.md#putting-a-question-to-the-hook-by-hand).
