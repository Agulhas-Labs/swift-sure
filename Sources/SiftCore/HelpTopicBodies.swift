//
// Copyright © Agulhas Labs
//

/// The long topic bodies, kept apart from ``HelpTopics`` so that type's own declaration stays under `type_body_length`.
struct HelpTopicBodies {
    static var testBody: String {
        """
        **The verdict line names the worst thing first** — `✔ \(ProductName.current.binary) test — 214 tests passed across 3 \
        shards`, or `✘ \(ProductName.current.binary) test — 4 failed · 1 missing · 1 duplicated`, with the exit code appended \
        where a failure's is not the plain `1`. Under it, the counts line reconciles the plan against \
        what every shard actually reported: `expected · ran · passed · failed · skipped · missing · \
        duplicated`. **Any *missing* or *duplicated* makes the run not green, whatever `xcodebuild` \
        said** — a test the plan assigned that never reported an ending, or one that reported twice, is \
        a shape no exit code speaks to.

        **A missing test is named by the shard that owed it** — `missing: shard 2: \
        DemoUnitTests/CalculatorTests/testAddition()` — and, under it, every crash report written \
        while the run was going, by name: the nearly-always cause of one.

        **Each shard answers with its own line**: tests run, wall clock against what the plan \
        predicted, the tests' own time against both, how many iterations it took, its exit code, and \
        its log path. Wall clock at more than twice the tests' own time draws a line saying so — launch, \
        session start and bundle load, all outside any one test's own time. Under the shard lines, one \
        line times the run itself, phase by phase — `build 12s · enumerate 7s · devices ready +30s · \
        shards 200s · teardown 6s` — where the enumeration runs while the devices boot, and `devices \
        ready` is the wait for them beyond the build and the enumeration they overlapped.

        **A shard is ended after no output for 300 s, or three times its longest predicted test where that is longer**, which is what a stuck one does; its wall \
        clock is only a ceiling, three times its predicted cost and never under an hour, since under \
        load a working shard's wall varies twofold. The notes say which bound fired — `ended after \
        Ns with no output for 300s` or `ended at its ceiling of Ns` — and name a `swift test` the \
        stall watch stopped. `--shard-timeout <seconds>` replaces the ceiling's floor for a caller who \
        has already measured that a suite never needs it (refused under 30); a shard ended at its \
        ceiling then says so, `(floor Ns, set by --shard-timeout)`, since the default floor needs no \
        reminder but a moved one does.

        **Shards boot slim where the runtime has a service profile and the project's declarations are \
        accounted for**, the override read back after the boot, and none of it fails a run. `--stock` \
        boots every shard stock and skips the settings read; refused beside `--sweep`, `--analyse`, SwiftPM.
        **Animations are off by default in the app under UI test** (UIKit only; SwiftUI animations still \
        run), through a library inserted into a copy of the `.xctestrun`, and the answer says so. A test keeps \
        them with `\(EnvironmentVariable.animations.name)=on` in its `launchEnvironment`; `--animations` keeps them for the whole \
        run, and is refused beside `--sweep`, `--analyse`, SwiftPM.

        **In a linked worktree the answer names where the build went** on its own line, `derived data \
        \(ProductName.current.directoryName)/DerivedData — inside this worktree, so it goes when the worktree is removed`, after the \
        devices line (and last under a failed build's output); the primary checkout and a caller's own \
        `-derivedDataPath` leave it out.

        **The devices line says how they booted, verdict first.** `slim: 93 of 338 services off (iOS \
        27.0, profile v1), kept for the project: healthKit 5, iCloud 12` is 93 of the profile's 338 \
        services switched off, the kept list being what the project's declarations needed. \
        `stock: <why>` names why a run booted stock: `--stock`, no profile for the runtime, \
        declarations that could not be read, or declarations no rule maps. Shards that differ are \
        grouped by number: `not slim on shard 3: …` (the override was not read back), `slim, unverified \
        on shard 4: …` (the read-back timed out). When tests failed after a slim boot, the re-run \
        command is followed by a sentence saying that adding `--stock` rules the slim boot out.

        **`slowest:` names the individual tests that cost the most, worst first.** A green run keeps it, a \
        SwiftPM package's too: `\(ProductName.current.binary) test` with no `--scheme` in a package runs `swift test` split by suite \
        across processes and creates no simulator.

        **Two sentences explain the plan, when either applies**: one where the shard count was lowered \
        from what was asked — too little work for it, or a predicted makespan that would not have paid \
        for another shard — and one where some tests had no recorded duration and were charged the \
        median of those that did.

        **A failure carries its own re-run line**: `re-run just these, serially: \(ProductName.current.binary) test --scheme \
        … --device … --shards 1 --only …` — the same invocation that ran, unsharded, on just the \
        failures — since a failure under N-way load is not yet a failure and the same shard run alone \
        may pass, so this is a way to find out rather than a verdict.

        **The sweep runs first, and reports what it found**: a device a dead run of this checkout left \
        behind, swept by prefix and udid before this run creates anything of its own, one line per \
        device it removed and one per device it could not. Under it, the devices line is this run's \
        own — `N simulators created, N deleted` — with any already gone called out, and a device a \
        delete could not remove named along with the command to remove it by hand. `\(ProductName.current.binary) test --sweep` \
        runs that sweep alone, without a run, and names each device it deleted.

        **Durations live in `\(ProductName.current.directoryName)/test-durations.json`**, which is what the lowered-shard and \
        estimated-charge sentences above are reading — a plain `\(ProductName.current.binary) run -- xcodebuild test` seeds it \
        too, so a plan's first run is never the only thing that feeds it.

        **`\(ProductName.current.binary) test --analyse` answers the other question, and shares none of the machinery above.** \
        It builds nothing, boots nothing and runs nothing: it reads the index for every declared test, \
        reads the `.xctestplan` files off disk, and prints the difference between them. Its verdict \
        line carries five figures with their arithmetic under it — `declared`, `in a plan`, `runs`, \
        `never runs`, and `conditional`, which is reported on its own and folded into neither of the \
        two beside it, because whether a `.enabled(if:)` test runs is decided at runtime and a count \
        that guessed would be wrong in one direction silently. A per-target table follows, and then \
        only the residue: a section with nothing in it is not printed at all.

        **The section worth reading first is whatever the answer found.** A test target no plan names \
        is reported by what the `.xcscheme` files say about it — run by a scheme's `TestAction` with no plan involved, run by nothing at all, or named by no plan and settled by no scheme read here. A `skippedTests` entry naming a \
        swift-testing test is ignored by Xcode and excludes nothing, and so is an XCTest entry whose \
        identifier carries no parentheses — both are named as having no effect, because a reader of \
        that plan believes something is excluded that is not. An entry that *is* honoured is named \
        too: it leaves no log line, no `.xcresult` node and a tally smaller by one, so the advice \
        beside it is to move the exclusion into the test, where every report shows it skipped with \
        its reason. An entry matching no declared test at all is its own case, and never folded into \
        those three.

        **`--plan <name>` narrows it to one plan**, and a name no plan under the repository carries is \
        refused with the names that were found. `--analyse` is refused together with every flag that \
        describes a build or a run — `--scheme`, `--device`, `--os`, `--shards`, `--shard-timeout`, \
        `--stock`, `--animations`, `--only`, `--skip`, `--project`, `--workspace` and anything after `--` — since there is nothing \
        here for one to name. **A repository with no plan at all is answered rather than refused**: SwiftPM has none \
        and `swift test` runs every test in every test target, so there `declared` is the expected set \
        and the answer says so in place of the plan sections.

        `\(ProductName.current.binary) test --help` has every flag.
        """
    }

    static var buildOutputBody: String {
        """
        **It builds, clean, unlike `\(ProductName.current.binary) test --analyse`.** It deletes `.build/\(ProductName.current.binary)-timing`, runs \
        `swift build --build-system native` into it with the compiler's two timers passed on the \
        command line, and reads what they printed; the manifest is never edited and your own `.build` \
        products are untouched. `--build-system native` is deprecated by SwiftPM, but on Swift 6.4 it \
        is the only one that prints the timings one per line, so a successful build that printed none \
        is refused, never read as nothing being slow — a future toolchain that drops it entirely will \
        need a different flag here.

        **The header is the build it ran** — `✔ \(ProductName.current.binary) build --analyse — clean build, 42.3s, 1,204 timing \
        lines over 87 files`. Under it, the slowest function bodies, then the slowest expressions, each \
        `file:line · ms · enclosing declaration`, with `(×N)` where one site was timed N times (a stored \
        property's initializer is checked in every frontend job that needs it; its synthesized accessors \
        are separate bodies at one place; batch mode is off, since a batch job's output is printed once per file of the batch). An expression row names its shape too, when it is one of three named at the site from the same parse — `long literal chain` (three or more `+` over literals), \
        `untyped mixed collection literal` (an array or dictionary literal with no type annotation on its binding and elements of more than one literal kind), or `ternary chain` (a ternary whose then or else branch is itself a ternary). Then the files holding the most body time, and the totals: \
        `bodies 12.4s of which the 10 listed are 61% · expressions 3.1s, listed 74%`. **A body's time \
        includes its expressions', so the two totals are never added.** Time spent in dependencies is \
        counted on a line of its own, function bodies and expressions outside any body apart, and never ranked. \
        So is time in a macro expansion's generated `@__swiftmacro_…` buffer, which names no file of the package: \
        its own `macro expansions:` line, bodies and expressions apart. A `deinit` row is named \
        `Type.deinit`, also for a class declared inside a function. `swift build` does not compile test targets, so \
        unless `--build-tests` was passed, and the package declares one, a line says the ranking covers the compiled targets only. The last line names the raw log under \
        `\(ProductName.current.directoryName)/runs/`.

        **SwiftPM only.** A tree with an Xcode project and no `Package.swift` is refused in one line; \
        `--root` names a package directory. A failed build is answered as `\(ProductName.current.binary) run` answers one, and \
        exits with the build's own code. `--top N` sets how many rows each list keeps (default 10).
        """
    }
}
