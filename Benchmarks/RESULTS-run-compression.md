# swift-sure run: compression, recall and precision (2026-10-22)

Question: how much does `swift-sure run -- <toolchain command>` shrink build and test output against the raw output
an agent would otherwise read, and does its answer keep every failure (recall) without naming one that is not
there (precision)? Measured, deterministic, no model calls.

**Binary:** `swift-sure --version` prints `0.1.8`, built in release from source at commit `106b2b013`
(`swift build -c release`), the same tree the clone below was taken from. Measured on 2026-10-22.
This replaces the 2026-10-01 measurement of the installed 0.1.0 (base `fa8a9622`).

**Not re-run: Corpus B.** The earlier file also replayed a real xcodebuild log of a private iOS app (2 cases).
That log is not in the tree, so those two cases could not run and are not in this table or its figures.
The earlier results for them were 100% fewer bytes with the one spliced error named; they say nothing about this binary.

## Method

- **Same run, both sides.** Each case runs `swift-sure run -- <command>` once. "sift" is its whole stdout, including
  the `raw: …` tail line. "raw" is the complete log sift filed under `.swift-sure/runs/` for that same run, which is
  what `<command> 2>&1` prints. Nothing is run twice, so incremental-build state cannot differ between the sides.
- **Corpus A, this repository:** a clone of 106b2b013 in a scratch directory. Each case appends injected
  code to source files or writes one new test file, runs, and restores every file byte for byte, checked by hash.
  `git status` in the clone was clean afterwards. The edits are in `Benchmarks/run-compression.py` (`CASES`).
- **Tokens** are estimated as bytes / 4. No offline tokenizer is installed, so token reduction equals byte
  reduction throughout.
- **Truth** is parsed from the raw log, ANSI colour stripped. It covers compiler `error:` lines (`warning:` lines
  for the warnings-only build), the driver's `error: path:line:col msg` form, XCTest `error: -[…]` lines,
  Swift Testing `✘ Test … recorded an issue` lines (one per parameterised argument),
  `Undefined symbols` entries, `Fatal error:` lines, `exited with unexpected signal`, and, when a process crashed,
  the test that started and never finished.
- **Recall (full)** means the answer names the location (`File.swift:line`), the test and argument where there
  is one, and the first 40 characters of the message. **Located** means place without message.
- **Precision** means every `File.swift:line` and every `name(` in the answer occurs in the raw log.
- **Baselines** are the same raw log through `tail -50` and `grep error:`, scored the same way. A
  build-output summariser was not installed, so it is not compared.
- **Corpus B (not run here):** a private iOS app's real xcodebuild log, replayed through a shim executable named
  `xcodebuild` (`replay --log <log> --cwd <dir> --out <out>`); see the note above.
- Reproduce, with the binary to measure passed explicitly:
  `python3 -I Benchmarks/run-compression.py capture --clone <clone> --out <out> --binary <path>/swift-sure`, then
  `python3 -I Benchmarks/run-compression.py report --out <out>`. The script finds the log from the answer's
  `raw:` line in either shape, the earlier `raw: <path>` and the current `raw: <tree stamp> · <path> (N lines in, M out), …`.
  Two cases are not in `CASES`: `build-clean` (the clone's first `swift-sure run -- swift build`) and the full-suite
  case (one unfiltered `swift-sure run -- swift test` of the pristine clone, 17 min here). Both were captured by
  calling the script's `run_sift` and `save` for that command, so a re-run of `capture` yields the other 16.

## Results

18 cases. The unfiltered full-suite run is named `test-full-red`, not `test-full-green` as before: on this clone it
failed (exit 1, 2 tests in `ReuseNudgeBatchTests` failing, 4 issues), so it is a red run and is scored as one. Why those
2 tests fail in a clone under `.build/` was not investigated.

| case | family | exit | raw lines / bytes / ~tok | sift lines / bytes / ~tok | byte reduction | sift recall (full+located/n) | invented | tail -50 bytes, recall | grep error: bytes, recall |
|---|---|---|---|---|---|---|---|---|---|
| build-clean | build-green | 0 | 228 / 7772 / 1943 | 3 / 190 / 47 | 98% | - | none | 1393, - | 0, - |
| build-errors-1 | build-errors | 1 | 22 / 22651 / 5662 | 6 / 382 / 95 | 98% | 1+0/1 | none | 22651, 1+0/1 | 705, 1+0/1 |
| build-errors-1-missing-return | build-errors | 1 | 17 / 22647 / 5661 | 6 / 399 / 99 | 98% | 1+0/1 | none | 22647, 1+0/1 | 792, 1+0/1 |
| build-errors-12 | build-errors | 1 | 136 / 34500 / 8625 | 21 / 2109 / 527 | 94% | 12+0/12 | none | 25359, 4+0/12 | 5645, 12+0/12 |
| build-errors-12-spread | build-errors | 1 | 9 / 9652 / 2413 | 6 / 352 / 88 | 96% | 1+0/1 | none | 9652, 1+0/1 | 433, 1+0/1 |
| build-errors-3 | build-errors | 1 | 21 / 104376 / 26094 | 6 / 402 / 100 | 100% | 1+0/1 | none | 104376, 1+0/1 | 594, 1+0/1 |
| build-linker | build-errors | 1 | 32 / 4504 / 1126 | 10 / 692 / 173 | 85% | 1+0/1 | none | 4504, 1+0/1 | 585, 0+1/1 |
| build-noop | build-green | 0 | 7 / 175 / 43 | 3 / 187 / 46 | -7% | - | none | 175, - | 0, - |
| build-warnings-5 | build-warnings | 0 | 68 / 4883 / 1220 | 11 / 999 / 249 | 80% | 5+0/5 | none | 4153, 4+0/5 | 0, 0+0/5 |
| build-warnings-as-errors-5 | build-errors | 1 | 38 / 25516 / 6379 | 9 / 803 / 200 | 97% | 3+0/3 | none | 25516, 3+0/3 | 2969, 3+0/3 |
| test-crash-swift-testing | test-crash | 1 | 44 / 2952 / 738 | 9 / 769 / 192 | 74% | 3+1/4 | none | 2952, 4+0/4 | 883, 2+0/4 |
| test-crash-xctest | test-crash | 1 | 38 / 2519 / 629 | 9 / 804 / 201 | 68% | 3+1/4 | none | 2519, 4+0/4 | 773, 4+0/4 |
| test-fail-1 | test-failures | 1 | 51 / 2327 / 581 | 5 / 436 / 109 | 81% | 1+0/1 | none | 2301, 1+0/1 | 0, 0+0/1 |
| test-fail-20 | test-failures | 1 | 134 / 9278 / 2319 | 52 / 3300 / 825 | 64% | 24+0/24 | none | 2998, 11+0/24 | 2199, 10+0/24 |
| test-fail-5 | test-failures | 1 | 57 / 3558 / 889 | 14 / 990 / 247 | 72% | 5+0/5 | none | 3350, 5+0/5 | 642, 3+0/5 |
| test-full-red | test-failures | 1 | 25056 / 2147489 / 536872 | 19 / 2108 / 527 | 100% | 4+0/4 | none | 3649, 0+0/4 | 5912, 0+0/4 |
| test-narrow-green | test-green | 0 | 134 / 11720 / 2930 | 3 / 224 / 56 | 98% | - | none | 7817, - | 0, - |
| test-timeout | test-failures | 1 | 24 / 966 / 241 | 5 / 388 / 97 | 60% | 1+0/1 | none | 966, 1+0/1 | 0, 0+0/1 |

- test-crash-swift-testing: not fully named (located): {'kind': 'crash', 'loc': None, 'msg': 'signal code 5'}
- test-crash-xctest: not fully named (located): {'kind': 'crash', 'loc': None, 'msg': 'signal code 5'}

Both are the crash itself (`signal code 5`): the answers name the signal, the crashed test and the `Fatal error:` line
in full, so the recall is complete in substance.

| green case | sift bytes | the raw output's own summary lines, bytes | those lines |
|---|---|---|---|
| build-clean | 190 | 29 | Build complete! (77.43 secs) |
| build-noop | 187 | 28 | Build complete! (2.33 secs) |
| build-warnings-5 | 999 | 29 | Build complete! (32.47 secs) |
| test-narrow-green | 224 | 95 | Build complete! (104.47 secs) / ✔ Test run with 8 tests in 1 suite passed after N seconds. |

| family | cases | median byte (= ~token) reduction | range |
|---|---|---|---|
| build-errors | 7 | 97% | 85% to 100% |
| build-green | 2 | 45% | -7% to 98% |
| build-warnings | 1 | 80% | 80% to 80% |
| test-crash | 2 | 71% | 68% to 74% |
| test-failures | 5 | 72% | 60% to 100% |
| test-green | 1 | 98% | 98% to 98% |
| **all 18 cases** | 18 | **89%** | -7% to 100% |

**Recall:** 66 of the 68 failures in the raw logs are named in full and the other 2 are the crash signal, located
(named as "signal 5"); 68 of 68 are named at least by location. Counting only this binary's own answers,
`tail -50` names 42 in full and `grep error:` 38. **Precision:** no case names a location or test that the raw log
lacks. The `test-fail-20` answer's count ("24 failures") matches the raw log.
**One answer is larger than its raw log: `build-noop`, 187 B against 175 B raw** (3 lines against 7). A no-op build
logs one `Build complete!` line plus a few lines of its own, shorter than the answer's header, `Build complete!` line
and `raw:` pointer (which now also carries the tree stamp). Every other case is smaller, by 60% to 100%.

### What changed since 2026-10-01

1. **A test process that traps** (#447): both crash answers now name the crashed test (`traps1()`,
   `-[SiftCoreTests.BenchInjectedXCTests testTraps1]`) and the `Fatal error:` line. Earlier they dropped both.
2. **The false "no closing summary line" sentence** on failing `swift build` answers is gone: no answer in this run
   contains it. (Repro that showed it: inject `func f() { undefinedName() }` into any package source file, then run `swift-sure run -- swift build`.)
3. **A tiny raw log still costs more than it saves**: see the no-op build above. It is the one regression in range:
   the earlier 116 B answer grew to 187 B, from the tree stamp on the `raw:` line.
4. `build-warnings-as-errors-5` now names 3 errors (the earlier run named 1); recall is scored against what the raw
   log reports, which is what an agent could have seen.

### The green runs: what swift-sure prints when everything passes

The table above lists each green case's answer against the toolchain's own summary lines. swift-sure prints more than
the toolchain's own summary line, never less; the extra bytes are the `✔ <tool>` headline and the `raw:` pointer.
An agent that already knows to read only that line saves about 130 to 160 bytes by skipping swift-sure. One that reads the
raw log, or `tail -50`, does not.

### Notes on the corpus

- `swift build` (the SwiftBuild backend) stops at the first failing compile job, so the injected count is not
  always the reported count (`build-errors-3` and `build-errors-12-spread` each report 1; `build-errors-12`, one
  file, reports 12). Recall is scored against what the raw log reports, which is everything an agent could have seen.
- The package sets `.treatAllWarnings(as: .error)` in its manifest, and `-Xswiftc -no-warnings-as-errors` does
  not override it. The warnings-only case therefore takes that line out of the manifest for its one run.
- The 20-failure case has 20 failing test functions and 24 issues: one test with two issues, and one
  parameterised test with four failing arguments.
- The timeout case uses Swift Testing's `.timeLimit(.minutes(1))` on a sleeping test.
- Not reproduced: a compiler crash. There is no reliable crasher on this toolchain. The crash reader has its
  own fixture tests (`RunCompilerCrashTests`).
- The `grep error:` baseline finds no Swift Testing failures at all, since its lines carry no `error:`. It also
  finds no warnings. `tail -50` loses 8 of 12 compile errors in `build-errors-12` and 13 of 24 test failures
  in `test-fail-20`.
