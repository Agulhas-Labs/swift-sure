//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SiftCore

/// `swift-sure test` — one scheme's tests across several simulators at once, answered with counts of this tool's own, and `--analyse`, which runs nothing and answers how many were supposed to.
struct TestCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Run a scheme's tests across several simulators at once, or a SwiftPM package's across several swift test processes.",
            discussion: """
            Builds the scheme once, splits the tests its plan enumerates across N simulators, runs one \
            xcodebuild per shard, and answers with one reconciliation — expected · ran · passed · failed · \
            skipped · missing · duplicated — counted against the enumerated set rather than read off the \
            tallies the runners printed. A test the plan assigned that never reported an ending, and one \
            that reported twice, make the run not green whatever xcodebuild said, and are named with the \
            shard they belong to. `\(ProductName.current.binary) help test-output` reads the answer line by line.

            The simulators are this tool's own: one per shard, created of the device type named, booted, \
            and deleted when the run ends — after a signal and after a crash too, by a watcher started \
            beside the run, and failing that by the next run's sweep. A device \(ProductName.current.binary) did not create is \
            never touched.

            **In a SwiftPM package, with no `--scheme` and no `--device`, it runs no simulator at all**: \
            it splits the package's `swift test` by suite across processes, `--shards N` sets how many, \
            and the answer is the same reconciliation, with the `slowest:` tests named on a green run too. \
            `--os`, `--plan`, `--only`, `--skip`, `--project`, `--workspace` and everything after `--` are \
            refused there, since they name nothing a `swift test` process takes.

            **`--plan <name>` names the plan to run; repeat it, or pass `--all-plans`, to run several from one \
            build.** The build names no plan, each plan is enumerated from its own `.xctestrun`, and the \
            (plan, test) items share one pool of simulators, so a device that has finished is deleted while \
            others still run. The answer is one verdict, a line per plan, the totals, every shard and one \
            `slowest:` list. With no plan named, the scheme's default plan runs. A plan that switches on a \
            sanitizer is refused in a run of several plans, since it builds products of its own: run it alone \
            with `--plan <name>`.

            `--root <dir>` runs the whole command as if started in that directory, without a `cd`: the \
            package or scheme, the build, the shards and the run record are that checkout's.

            `--analyse` is the other half and shares none of that: it builds nothing, boots nothing and \
            runs nothing. It reads the index for every declared test, reads the `.xctestplan` files off \
            disk, and answers with the difference — how many tests are supposed to run, which of them \
            never will, and which plan exclusions do nothing at all. `--plan <name>` narrows it to one \
            plan.

            `--analyse --against <log>` closes the join at the other end: it reads a run's own output \
            back and reconciles it against that same declared inventory, so a test that never started \
            is named as missing instead of vanishing from the tally. It builds and boots nothing either \
            — the run already happened, and the file is all it reads. The expected set is bounded by \
            this package's test targets, and the run is not green with anything missing or duplicated, \
            whatever its own summary line said.

            Examples:
              \(ProductName.current.binary) test --scheme Gizmo --device "iPhone 17" --plan Unit --shards 3
              \(ProductName.current.binary) test --analyse
              \(ProductName.current.binary) test --sweep
              swift test > run.log 2>&1; \(ProductName.current.binary) test --analyse --against run.log
            """
        )
    }

    @Flag(name: .customLong("analyse"), help: "Answer how many tests are supposed to run, from the index and the plans. Builds nothing, boots nothing, runs nothing.")
    var analyse: Bool = false

    @Flag(name: .customLong("sweep"), help: "Delete the simulators left by this checkout's runs that are no longer running, and run nothing.")
    var sweep: Bool = false

    @Option(name: .customLong("scheme"), help: "The scheme to build and run.")
    var scheme: String?

    @Option(name: .customLong("device"), help: "The device type to create the simulators of, as `simctl list devicetypes` spells it.")
    var device: String?

    @Option(name: .customLong("os"), help: "The runtime version to create them on. Defaults to the newest installed one that runs the device type.")
    var osVersion: String?

    @Option(name: .customLong("plan"), help: "The test plan to run. Repeat it to run several plans from one build, on one pool of simulators; with none, the scheme's default plan runs.")
    var plan: [String] = []

    @Flag(name: .customLong("all-plans"), help: "Run every test plan of the scheme from one build, on one pool of simulators.")
    var allPlans: Bool = false

    @Option(name: .customLong("against"), help: "Reconcile a finished run's output against the declared inventory: the file `swift test` wrote, or a log kept under \(ProductName.current.directoryName)/runs/. Needs --analyse.")
    var against: String?

    @Option(name: .customLong("only"), help: "Run only this Target, Target/Class or Target/Class/test. Repeatable.")
    var only: [String] = []

    @Option(name: .customLong("skip"), help: "Leave out this Target, Target/Class or Target/Class/test. Repeatable.")
    var skip: [String] = []

    @Option(name: .customLong("shards"), help: "How many simulators to split the tests across. Defaults to what this host can run at once.")
    var shards: Int?

    @Option(name: .customLong("shard-timeout"), help: "The floor under a shard's wall-clock ceiling, in seconds. Defaults to 3600 (an hour); refused below 30. A shard silent for 300 s is ended whatever this says.")
    var shardTimeout: Int?

    @Flag(name: .customLong("stock"), help: "Boot every shard stock, with no simulator services switched off, and skip the build-settings read: the other arm of a comparison, or the way out while a service profile is wrong.")
    var stock: Bool = false

    @Flag(name: .customLong("animations"), help: "Leave animations on in the app under UI test. By default a library switches UIKit animations off at launch; one test keeps them by setting \(EnvironmentVariable.animations.name)=on in its launchEnvironment.")
    var animations: Bool = false

    @Option(name: .customLong("project"), help: "The .xcodeproj the scheme lives in. Found in the working directory or the repository root when neither this nor --workspace is given.")
    var project: String?

    @Option(name: .customLong("workspace"), help: "The .xcworkspace the scheme lives in, instead of --project.")
    var workspace: String?

    @Argument(parsing: .postTerminator, help: "Everything after --, handed to xcodebuild untouched.")
    var passThrough: [String] = []

    /// The watcher a sharded run starts to delete its simulators if it is killed; never typed by a person.
    @Option(name: .customLong("guard-shards"), help: .private)
    var guardShards: String?

    @OptionGroup var rootOptions: RootOptions

    /// Where the answer goes, injected so a test can read what the command printed.
    var output: CommandOutput = .standard

    /// How `--sweep` spawns `simctl`, injected so a test deletes nothing real.
    var simctl: @Sendable (String, [String]) throws -> Subprocess.Output = TestRunEnvironment.liveSimctl()

    /// The lease store `--sweep` reads a device's holder from and gives a deleted device's lease up in, injected so a test reads no real lease.
    var leases: ShardLeases? = .shared

    /// The directory the command reads its repository from: the process's own unless a test names another.
    var startingDirectory: URL?

    /// How a package run is carried out, injected so a test hands back a reconciliation without building anything.
    var runPackage: @Sendable (PackageTestRun) -> TestRunResult = { $0.run() }

    /// The per-user run log a run is filed in, injected so a test files none in the real one.
    var usageLog = RunUsageLog.standard(note: { StandardStreams.emitError($0) })

    /// The environment ``RunLedger/isOn(environment:)`` is read from, injected so a test switches the ledger off for one run without setting a variable every suite running beside it would read.
    var environment: [String: String] = ProcessInfo.processInfo.environment

    /// The arguments the user gave `test`, which with the log key's words make the invocation a run is filed under, injected so a test names them.
    var givenArguments: [String] = Array(CommandLine.arguments.dropFirst().drop { $0 == "test" })

    /// The least `--shard-timeout` will set the bound to — low enough to matter, high enough that it can never fire on a shard that only just launched `xcodebuild`.
    static let minimumShardTimeoutSeconds = 30

    /// The refusals `--analyse` is owed before anything is opened, since every flag below describes a build or a run it will not do.
    ///
    /// Each one is a sentence rather than a usage dump: a caller who pasted a working `swift-sure test` line and added `--analyse` has asked for two different commands at once, and the thing they need told is which half this flag drops.
    func validate() throws {
        if sweep {
            try validateSweep()
        }
        guard plan.isEmpty || !allPlans else {
            throw ValidationError("--plan and --all-plans choose the plans two different ways: --all-plans runs every plan of the scheme, and --plan runs the ones it names. Drop --all-plans to run the named plans, or every --plan to run them all.")
        }
        guard analyse else {
            guard against == nil else {
                throw ValidationError("--against reads a run that has already happened and reconciles it against the index, which is --analyse's half of this command. Pass --analyse --against <log>, or drop --against to run the tests.")
            }
            return
        }
        guard plan.count < 2, !allPlans else {
            throw ValidationError("--analyse reads every plan when none is named, and --plan <name> narrows it to one; it takes one --plan and no --all-plans. Drop the extra plans.")
        }
        guard against == nil || plan.isEmpty else {
            throw ValidationError("--against and --plan bound the expected set two different ways: --plan narrows to one .xctestplan's container, and --against reconciles a `swift test` run, which reads no plan and covers this package's test targets. Drop one of the two.")
        }
        let refused: [(name: String, given: Bool)] = [
            ("--scheme", scheme != nil),
            ("--device", device != nil),
            ("--os", osVersion != nil),
            ("--shards", shards != nil),
            ("--shard-timeout", shardTimeout != nil),
            ("--stock", stock),
            ("--animations", animations),
            ("--only", !only.isEmpty),
            ("--skip", !skip.isEmpty),
            ("--project", project != nil),
            ("--workspace", workspace != nil),
            ("--guard-shards", guardShards != nil),
            ("everything after --", !passThrough.isEmpty),
        ]
        guard let first = refused.first(where: \.given) else {
            return
        }
        throw ValidationError("--analyse and \(first.name) ask for two different things: --analyse reads the index and the test plans and starts no build, boots no simulator and runs no test, so there is nothing for \(first.name) to name. Drop one of the two.")
    }

    /// The directory the whole command runs as if started in: the one a test names, else `--root`, else the process's own.
    ///
    /// `--root` is spelled as `run --root` spells it, so a relative one is joined to the logical directory and `..` after a symbolic link lands where a shell `cd` does. The process does not move: the directory is handed down, and every reading of the repository starts from it.
    func commandDirectory() throws -> URL {
        if let startingDirectory {
            return startingDirectory
        }
        guard let root = rootOptions.root else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        let logical = RunRootPath.logical(
            root,
            inheritedPWD: ProcessInfo.processInfo.environment["PWD"],
            current: FileManager.default.currentDirectoryPath
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: logical, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ValidationError("\(ProductName.current.binary) test --root: \(root) is not a directory.")
        }
        return URL(fileURLWithPath: logical)
    }

    func run() async throws {
        let workingDirectory = try commandDirectory()
        if sweep {
            guard let repositoryRoot = try GitContext.enclosingRoot(from: workingDirectory) else {
                throw ValidationError("\(ProductName.current.binary) test --sweep runs inside a git repository: the records of which simulators its runs created live in that repository's \(ProductName.current.directoryName)/.")
            }
            let report = try ShardSweep.sweep(repositoryRoot: repositoryRoot, prefix: ShardLedger.devicePrefix(in: repositoryRoot), leases: leases, run: simctl)
            output.emit(report.answer)
            guard report.exitCode == 0 else {
                throw ExitCode(report.exitCode)
            }
            return
        }
        if analyse {
            let (answer, isGreen) = try await analysis(workingDirectory: workingDirectory)
            output.emit(answer)
            guard isGreen else {
                throw ExitCode(1)
            }
            return
        }
        if let guardShards {
            throw ExitCode(ShardGuardian.watch(runID: guardShards, repositoryRoot: workingDirectory))
        }
        if let package = try packageRun(in: workingDirectory) {
            let interruptions = TestInterruptions()
            interruptions.arm { package.cancel(exitCode: 128 + $0) }
            let repositoryRoot = GitContext.discoverRoot(from: workingDirectory)
            let treeBefore = repositoryRoot.flatMap { TreeKey.of(repositoryRoot: $0) }
            let startedOn = runKey(in: repositoryRoot, from: workingDirectory)
            let started = Date()
            let result = withExtendedLifetime(interruptions) { runPackage(package) }
            output.emit(result.answer)
            if let repositoryRoot {
                let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
                record(result, milliseconds: milliseconds, repositoryRoot: repositoryRoot, startedOn: startedOn)
                prove(result, treeBefore: treeBefore, milliseconds: milliseconds, workingDirectory: workingDirectory, repositoryRoot: repositoryRoot)
            }
            guard result.exitCode == 0 else {
                throw ExitCode(result.exitCode)
            }
            return
        }
        let request = try request(in: workingDirectory)
        let run = TestRun(request: request)
        // Armed before the run rather than after it starts: between the two is exactly the window in which a
        // device has been created and nothing is yet listening for the signal that would otherwise leave it.
        let interruptions = TestInterruptions()
        interruptions.arm { run.cancel(exitCode: 128 + $0) }
        let startedOn = runKey(in: request.repositoryRoot, from: workingDirectory)
        let started = Date()
        let result = withExtendedLifetime(interruptions) { run.run() }
        output.emit(result.answer)
        record(result, milliseconds: Int(Date().timeIntervalSince(started) * 1000), repositoryRoot: request.repositoryRoot, startedOn: startedOn)
        guard result.exitCode == 0 else {
            throw ExitCode(result.exitCode)
        }
    }

    /// `--sweep` refuses every flag that describes a run, and `--analyse`, by name, since it builds, boots and runs nothing.
    private func validateSweep() throws {
        let refused: [(name: String, given: Bool)] = [
            ("--analyse", analyse),
            ("--scheme", scheme != nil),
            ("--device", device != nil),
            ("--os", osVersion != nil),
            ("--plan", !plan.isEmpty),
            ("--all-plans", allPlans),
            ("--against", against != nil),
            ("--shards", shards != nil),
            ("--shard-timeout", shardTimeout != nil),
            ("--stock", stock),
            ("--animations", animations),
            ("--only", !only.isEmpty),
            ("--skip", !skip.isEmpty),
            ("--project", project != nil),
            ("--workspace", workspace != nil),
            ("--guard-shards", guardShards != nil),
            ("everything after --", !passThrough.isEmpty),
        ]
        guard let first = refused.first(where: \.given) else {
            return
        }
        throw ValidationError("--sweep and \(first.name) ask for two different things: --sweep deletes the simulators left by this checkout's runs that are no longer running, and builds, boots and runs nothing. Drop one of the two.")
    }

    /// `--analyse`'s whole answer, header first and any adopted-root note under it.
    ///
    /// The engine is opened the way every index-reading command opens it, because this half of `test` is a query over the index rather than a run: it needs the same freshening, and it owes the same header.
    ///
    /// The verdict is `true` for the static answer, which reports what is declared and passes judgement on no run.
    func analysis(workingDirectory: URL, registry: RootsRegistry = .standard()) async throws -> (answer: String, isGreen: Bool) {
        let (engine, note) = try rootOptions.makeEngine(registry: registry)
        let freshness = try await engine.ensureFresh()
        guard let against else {
            return try (Freshness.placing([note], under: engine.analyseTests(plan: plan.first, freshness: freshness)), true)
        }
        let logURL = URL(fileURLWithPath: against, relativeTo: workingDirectory).standardizedFileURL
        let reconciliation = try engine.reconcileTests(against: logURL, freshness: freshness)
        return (Freshness.placing([note], under: reconciliation.answer), reconciliation.isGreen)
    }

    /// The SwiftPM run these flags describe — no `--scheme`, no `--device`, and a `Package.swift` in the working directory — or `nil` where they describe a simulator run.
    ///
    /// Every flag that names a simulator, a plan or an `xcodebuild` argument is refused by name, since a package's shards are `swift test` processes and there is nothing for it to name.
    func packageRun(in workingDirectory: URL) throws -> PackageTestRun? {
        guard scheme == nil, device == nil, FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent("Package.swift").path) else {
            return nil
        }
        let refused: [(name: String, given: Bool)] = [
            ("--os", osVersion != nil),
            ("--plan", !plan.isEmpty),
            ("--all-plans", allPlans),
            ("--only", !only.isEmpty),
            ("--skip", !skip.isEmpty),
            ("--project", project != nil),
            ("--workspace", workspace != nil),
            ("everything after --", !passThrough.isEmpty),
        ]
        if let first = refused.first(where: \.given) {
            throw ValidationError("\(ProductName.current.binary) test with no --scheme runs this SwiftPM package's `swift test` split by suite across processes, and \(first.name) names nothing there. Pass --scheme and --device for a simulator run, or drop \(first.name).")
        }
        if stock {
            throw ValidationError("--stock chooses how simulators boot, and a SwiftPM package run boots none. Drop --stock.")
        }
        if animations {
            throw ValidationError("--animations keeps animations on in a simulator app under UI test, and a SwiftPM package run launches no app. Drop --animations.")
        }
        if let shards, !(1 ... ShardPlanner.maximumShards).contains(shards) {
            throw ValidationError("--shards \(shards) is not a count of `swift test` processes \(ProductName.current.binary) will run: it takes 1 to \(ShardPlanner.maximumShards), and 1 splits nothing.")
        }
        if let shardTimeout, shardTimeout < Self.minimumShardTimeoutSeconds {
            throw ValidationError("--shard-timeout \(shardTimeout) is below \(Self.minimumShardTimeoutSeconds): a bound that low fires on a healthy shard before swift test has even loaded its bundle.")
        }
        guard let repositoryRoot = try GitContext.enclosingRoot(from: workingDirectory) else {
            throw ValidationError("\(ProductName.current.binary) test runs inside a git repository: the shard logs and the test durations live in that repository's \(ProductName.current.directoryName)/.")
        }
        return PackageTestRun(
            packageDirectory: workingDirectory,
            repositoryRoot: repositoryRoot,
            requestedShards: shards,
            shardTimeoutSeconds: shardTimeout.map(TimeInterval.init)
        )
    }

    /// The request these flags describe, or the refusal the caller is owed before anything is launched.
    ///
    /// Not `private`: the bound checks below run before any filesystem or process work, so a test reaches them directly through `@testable import` rather than through `run()`, which would otherwise have to build and boot to exercise them.
    func request(in workingDirectory: URL) throws -> TestRunRequest {
        guard let scheme else {
            throw ValidationError("\(ProductName.current.binary) test needs --scheme <name>: it builds and runs one scheme.")
        }
        guard let device else {
            throw ValidationError("\(ProductName.current.binary) test needs --device \"<device type>\", as `simctl list devicetypes` spells it: it names both what is created and what the one build is made for.")
        }
        if let shards, shards < 1 {
            throw ValidationError("--shards \(shards) is not a count of simulators: it takes 1 or more, and 1 splits nothing.")
        }
        if let shards, shards > ShardPlanner.maximumShards {
            throw ValidationError("--shards \(shards) is more than \(ProductName.current.binary) will ever plan onto: each shard is a booted simulator — roughly 2–4 GB and a core or two — so \(ShardPlanner.maximumShards) is the most, and this host's own default never goes above 6.")
        }
        if let shardTimeout, shardTimeout < Self.minimumShardTimeoutSeconds {
            throw ValidationError("--shard-timeout \(shardTimeout) is below \(Self.minimumShardTimeoutSeconds): a bound that low fires on a healthy shard before xcodebuild has even launched, and costs the whole suite it was given.")
        }
        guard let repositoryRoot = try GitContext.enclosingRoot(from: workingDirectory) else {
            throw ValidationError("\(ProductName.current.binary) test runs inside a git repository: the ledger that says which simulators to delete, the shard logs and the test durations all live in that repository's \(ProductName.current.directoryName)/.")
        }
        guard let executable = Bundle.main.executableURL else {
            throw ValidationError("this process cannot name its own executable, and the watcher that deletes this run's simulators after a kill is a detached copy of it.")
        }
        return try TestRunRequest(
            scheme: scheme,
            deviceTypeName: device,
            osVersion: osVersion,
            plans: plan,
            allPlans: allPlans,
            only: only,
            skip: skip,
            container: container(workingDirectory: workingDirectory, repositoryRoot: repositoryRoot),
            passThrough: passThrough,
            derivedDataPath: WorktreeDerivedData.chosen(repositoryRoot: repositoryRoot, passThrough: passThrough),
            requestedShards: shards,
            shardTimeoutSeconds: shardTimeout.map(TimeInterval.init),
            workingDirectory: workingDirectory,
            repositoryRoot: repositoryRoot,
            executable: executable,
            stock: stock,
            animations: animations
        )
    }

    /// The project or workspace to build: the one named, the one the working directory and then the repository root decide on, or `nil` for a SwiftPM package — `xcodebuild` resolves a package's own scheme from its manifest with neither flag.
    ///
    /// The refusals arrive as this command's own validation errors so that a caller who has to add a flag is shown which one, under the usage that lists it.
    private func container(workingDirectory: URL, repositoryRoot: URL) throws -> TestInvocation.Container? {
        if let project {
            guard workspace == nil else {
                throw ValidationError("--project and --workspace name the same thing two ways: give one.")
            }
            return .project(project)
        }
        if let workspace {
            return .workspace(workspace)
        }
        let workingDirectoryNames = (try? FileManager.default.contentsOfDirectory(atPath: workingDirectory.path)) ?? []
        let sameDirectory = repositoryRoot.standardizedFileURL == workingDirectory.standardizedFileURL
        let repositoryRootNames = sameDirectory ? [] : (try? FileManager.default.contentsOfDirectory(atPath: repositoryRoot.path)) ?? []
        do {
            return try TestContainerChoice.chosen(
                inWorkingDirectory: workingDirectory,
                names: workingDirectoryNames,
                andRepositoryRoot: sameDirectory ? nil : repositoryRoot,
                names: repositoryRootNames
            )
        } catch let error as TestContainerError {
            throw ValidationError(error.description)
        }
    }

    /// Files a package run in the proved ledger as `swift test` run on the tree it read, as ``RunCommand`` files that run, so `run --proved -- swift test` stands on it.
    ///
    /// Only where the shards ran and the tree key was the same before the build and after the last shard: a green is a proof, a red revokes an earlier proof of the tree. A build that failed, a listing that named nothing, an interruption before the shards, a tree that moved and a toolchain that will not name itself record nothing. Best-effort, as the proof it mirrors.
    private func prove(_ result: TestRunResult, treeBefore: TreeKey?, milliseconds: Int, workingDirectory: URL, repositoryRoot: URL) {
        guard let reconciled = result.reconciled, let treeBefore, TreeKey.of(repositoryRoot: repositoryRoot) == treeBefore,
              !reconciled.isGreen || RunLedger.isOn(environment: environment),
              let toolchain = ToolchainIdentity.current()
        else {
            return
        }
        let asked = ["swift", "test"]
        let record = RunLedger.Record(
            tree: treeBefore.value,
            command: ProofKey.command(of: asked),
            toolchain: toolchain.description,
            finishedAt: Date(),
            log: nil,
            milliseconds: milliseconds,
            checkout: repositoryRoot.path,
            workingDirectory: RunDirectory.name(of: workingDirectory, relativeTo: repositoryRoot),
            arguments: asked,
            exitCode: reconciled.isGreen ? nil : result.exitCode,
            stoppedBySift: reconciled.isGreen ? nil : reconciled.stoppedBySift,
            runToken: result.runToken,
            shards: result.shards
        )
        let ledger = RunLedger.inRepository(at: repositoryRoot, note: { StandardStreams.emitError($0) })
        if reconciled.isGreen {
            ledger.recordGreen(record)
        } else {
            ledger.recordFailure(record)
        }
    }

    /// The content this run starts on and the command it was given, for `flakes` to key its outcomes by, or `nil` outside a repository.
    ///
    /// The command is the log key's words followed by what the user gave `test`, so `test --shards 3` and `test --shards 2 --filter X` are two invocations. Taken before the shards start, because afterwards it would be the tree the run left, not the one it read.
    private func runKey(in root: URL?, from workingDirectory: URL) -> TreeContentHash.RunKey? {
        guard let root else {
            return nil
        }
        return TreeContentHash.runKey(of: ProductName.testRunLogKey.split(separator: " ").map(String.init) + givenArguments, in: workingDirectory, repositoryRoot: root)
    }

    /// Files this run in the per-user run log, after the answer has already gone out, as a wrapped `swift-sure run` files itself, with the failing tests, the tree it started on and the invocation it was given.
    ///
    /// It files under its own name rather than under the `xcodebuild test-without-building` its shards ran: one sharded run is one thing that happened, and the several commands inside it are already kept, in full, under `.swift-sure/runs/`.
    ///
    /// The failing tests are the reconciliation's own, carried on the result and never read back out of the answer's text; a run that cannot say what failed in it files none, which `flakes` counts as unrecorded.
    private func record(_ result: TestRunResult, milliseconds: Int, repositoryRoot: URL, startedOn: TreeContentHash.RunKey?) {
        usageLog.record(
            logKey: ProductName.testRunLogKey,
            exitCode: result.exitCode,
            answer: RunUsageLog.Answer(lines: result.answer.split(separator: "\n", omittingEmptySubsequences: false).count, failedTests: result.failedTests),
            repositoryRoot: repositoryRoot,
            milliseconds: milliseconds,
            startedOn: startedOn
        )
    }
}

extension TestCommand {
    /// Only the flags, options and arguments come off the command line.
    ///
    /// Spelled out for the reason ``RunCommand``'s keys are: a stored property that is not an argument would otherwise have to be `Decodable` too, and neither an output nor a `simctl` runner is something a decoder can produce.
    enum CodingKeys: String, CodingKey {
        case analyse
        case sweep
        case scheme
        case device
        case osVersion
        case plan
        case allPlans
        case against
        case only
        case skip
        case shards
        case shardTimeout
        case stock
        case animations
        case project
        case workspace
        case passThrough
        case guardShards
        case rootOptions
    }
}
