# Running Builds and Tests

Wrap `swift build`, `swift test` and `xcodebuild` in `swift-sure run --` and read what comes back.

## Overview

Put `swift-sure run --` in front of the command you were going to run anyway:

```sh
swift-sure run -- swift test
swift-sure run -- swift build --build-tests
swift-sure run -- xcodebuild -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The command runs unchanged and its exit code is passed through, with the exceptions below. What changes is
the output: the verdict, the counts and what failed, instead of the whole log. These examples run in the
small package from <doc:GettingStarted>, a module called `Stacks` with three tests.

### A passing run

```text
$ swift-sure run -- swift test
✔ swift test
totals: ✔ passed · Swift Testing 3 tests in 1 suite, 0 skipped
inventory: 3 declared, 3 reported
raw: Shelf @ ec26cde (Swift clean) · .swift-sure/runs/run-20261012-114242Z-22220e76.log (20 lines in, 4 out), kept for the next 4 runs
```

- The first line is the verdict.
- `totals:` is the sum of the test tool's own tally lines, across Swift Testing and XCTest. A skipped test is
  counted as skipped (`0 skipped` when none was), so a run whose tests all skipped does not read as tests that
  ran, and each skipped test is named under it as `skipped: Suite.test — reason`.
- `inventory:` appears on an unfiltered `swift test`. It sets the tests the index declares against the ones
  the run reported, so a test that silently never ran shows up as a difference. Without an index it says it
  was not checked.
- `raw:` names the tree and commit the run happened in (`Shelf @ ec26cde (Swift clean)`, the word Swift saying the count covers only Swift files; the `tree:` header
  words the rest), then the complete output, written as it arrived, with the number of lines it stands for and the
  number shown. Nothing is lost: one file per run under `.swift-sure/runs/`, kept for the next four runs, and a failed run's
  log until that run passes or five newer failures follow it.

### A failing run

A failure keeps what you can act on: errors with file and line, test failures with their messages, and
warnings grouped by message (the first site shown with `×N`, the others in the raw log), and drops the rest. To reproduce this one in the sample package, change `== 1` to
`== 2` on the `overdue` line of `LibraryTests.swift`.

```text
$ swift-sure run -- swift test
✘ swift test — exit 1
  overdueCountsLongLoans() — Tests/StacksTests/LibraryTests.swift:32 (body :28-33)
    Expectation failed: library.overdue(after: 14).count == 2 → false library.overdue(after: 14).count → 1
totals: ✘ failed · Swift Testing 3 tests in 1 suite, 1 failing, 0 skipped
inventory: 3 declared, 3 reported
raw: Shelf @ ec26cde (Swift dirty: 1) · .swift-sure/runs/failed-8dd8a8d4-run-20261012-114245Z-372ad573.log (25 lines in, 6 out), kept until it passes or 5 newer failures
```

The heading names the file and line and, where the failure is inside the test's own body, that body's range.
If the command exits nonzero and the filter finds no error and no test failure to show, you get the whole raw
transcript instead of a summary of nothing.

### Run some of the tests

Name tests the way `swift test` does, with `swift-sure run -- swift test --filter`:

```text
$ swift-sure run -- swift test --filter overdueCountsLongLoans
✔ swift test
totals: ✔ passed · Swift Testing 1 test in 1 suite, 0 skipped
raw: Shelf @ ec26cde (Swift clean) · .swift-sure/runs/run-20261012-114244Z-27c3ca3a.log (10 lines in, 3 out), kept for the next 4 runs
```

A filtered run does not print `inventory:`, since it was asked to run fewer tests than are declared. For
`xcodebuild test` the equivalent is `-only-testing:`.

SwiftSure overrides the wrapped exit code in these cases only. A run that names its tests and executes none of
them, such as a filter that matches nothing, or one of several filters matching no test, exits 4 with
`✘ swift test — nothing ran`, naming the filter; `swift test` itself exits 0 there, which reads as success. An
unfiltered `swift test` of a package that declares test targets and executes no test exits 4 as well. Exit 5
means a run that names its tests failed to build before any test started. All are SwiftSure's own; a run that names
no tests keeps the wrapped command's exit when its build fails.

### Ask whether a tree already passed

A green run is remembered against the content of the tree. `--proved` answers from that record without
running anything:

```text
$ swift-sure run --proved -- swift test
tree-content: 8cf5dd2c9cd2  command: swift test
✔ proved — swift test passed 2s ago on this exact tree content, under this toolchain
  run run-20261005-093443Z-8eb81821.log in ~/code/Shelf, which took 1s — that much not spent again
  not covered: anything git does not track — the build directory, this tool's own state, the environment, the machine; the record is refused past 60m for exactly that reason
```

It exits 0 when this exact tree passed, 1 when no run is on record, and 2 when the question cannot be put.
A red run of the same command on the same content afterwards revokes the record. The proof does not cover
anything git does not track, and it expires after an hour.

### More

`swift-sure run` has more than this: `--coverage` lists which changed lines the tests ran, `--without` proves a
test fails without your change in a single call, `swift-sure test --shards` splits a slow simulator suite, and
`swift-sure affected` names the tests a diff could have broken. Anything other than `swift build`, `swift test`
and `xcodebuild` runs untouched, with one note on stderr saying so.

## Next steps

The guide's section on
[builds and tests](https://github.com/Agulhas-Labs/swift-sure/blob/main/Docs/Guide.md#12-builds-and-tests--swift-sure-run-swift-sure-test-swift-sure-build)
documents every option, and
[proving a test fails without your change](https://github.com/Agulhas-Labs/swift-sure/blob/main/Docs/Guide.md#proving-a-test-fails-without-your-change----without)
covers `--without`. For the query tools that run beside it, see <doc:TheFourTools>.
