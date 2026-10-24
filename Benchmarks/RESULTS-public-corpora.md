# Results: three public corpora, 0.3.0 candidate against 0.2.2 (2026-10-24)

The pre-release bench of 0.3.0, on the three corpora of
[fieldwork-bench](https://github.com/Agulhas-Labs/fieldwork-bench), which anyone can re-run: wikipedia-ios at
`27a82770`, firefox-ios at `d284ab8e` and swift-format at `b15dd59f`, each with its `tasks.json` at fieldwork-bench
`588d41f`. Sonnet 5.5, effort medium, Claude Code 2.1.310. Each corpus ran twice from one checkout, once with the 0.2.2
release binary (`0834a89b`) in arm B and once with the 0.3.0 candidate (`492d80d23`), each session on 6 run paths with 2
repeats per arm on each, so a corpus of 10 tasks is 240 scored runs per session and swift-format's 4 tasks are 96.
Every run was valid and correct in both arms and both sessions. Arm A has no SwiftSure; arm B has the default install
(index, MCP server, hooks, rule). Intervals are 95% bootstrap intervals over the paths. Session price is defined in
[README.md](README.md).

wikipedia-ios and firefox-ios are built for their index (`index_build` in the task file), so arm B's `where` answers from
the compiler's index store. swift-format is a SwiftPM package with no index build, so arm B's lookups fall back to written
names: its figure is mostly what `run` saves on builds and tests, less the index's fixed start, not a measure of the index.

## The candidate against no SwiftSure

| corpus | tasks | session price, with SwiftSure against without | 95% interval of the difference |
| --- | --- | --- | --- |
| wikipedia-ios | 10 short lookups and fixes | +6.1% | [+0.7k, +21.9k] |
| firefox-ios | 10 short lookups and fixes | +7.0% | [+7.2k, +16.7k] |
| swift-format | 4 build and test fixes | -5.3% | [-9.4k, -2.1k] |

On the two apps the tasks are short, and one or two lookups do not earn back the fixed start (arm B's first call
carries 1.2k more tokens of context: tool definitions, rule and session primer). The tasks that paid were tracing UI text
(wikipedia-ios -8.8% [-2.1k, -0.7k], firefox-ios -10.1% [-3.7k, -0.4k]) and one type's cases in firefox-ios (-3.8%);
a definition lookup answered by one `where --decl` call costs the fixed start and little else (+13.9%, +18.2%).

On swift-format, fixing a build error cost 33.9% less [-15.9k, -11.1k]: arm A read the raw `swift build` output, arm B
read `run`'s answer. Two locate-and-fix tasks whose tests were already filtered to one suite cost 13% more each (the fixed
start, with output small in both arms), and reporting a suite's failures showed no detectable difference (+7.0%,
[-0.6k, +3.9k]).

## The candidate against 0.2.2

Arm B of the candidate session against arm B of the 0.2.2 session, paired by path (`bench.py compare --arm B`).

| corpus | cheaper | dearer | no detectable difference |
| --- | --- | --- | --- |
| wikipedia-ios | 2 (-1.9k, -0.3k) | 1 (+0.2k) | 7 |
| firefox-ios | 4 (-3.2k, -3.1k, -0.3k, -0.2k) | 1 (+0.7k) | 5 |
| swift-format | 0 | 0 | 4 |

The +0.2k on wikipedia-ios is a definition lookup whose `where --decl` answer now carries the declaration's six lines
of source, which that task did not need and others do. The +0.7k on firefox-ios is a task neither session's arm B
answered with a SwiftSure call (Grep only in both), so it is not SwiftSure's difference. The rule is 164 tokens shorter
in the candidate (261 against 425, chars/4).
