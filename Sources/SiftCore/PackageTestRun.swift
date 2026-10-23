//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// One SwiftPM package's tests split by suite across several `swift test` processes at once, answered with the same reconciliation a simulator run is.
///
/// **Built once, then run past the build directory's lock.** SwiftPM locks `.build` for every command, so two `swift test` processes on one package wait on each other and the shards would run one after another. Every shard is `swift test --skip-build --ignore-lock`: it builds nothing, so the lock guards nothing it does, and the one build before it took the lock as usual.
///
/// **The expected set is what `swift test list` prints** over the build just made, the way a simulator run's is what `xcodebuild` enumerates, so the counts are this tool's own and a shard that dies leaves its tests missing rather than out of the arithmetic.
public final class PackageTestRun: @unchecked Sendable {
    private let packageDirectory: URL
    private let repositoryRoot: URL
    private let requestedShards: Int?
    private let shardTimeoutSeconds: TimeInterval?
    private let performanceCores: Int
    private let children = SetAsideChildren()
    /// The token every log of this run carries, so the build, the listings and the shards are one run to the count that prunes transcripts.
    private let runToken: String
    private let gate = NSLock()
    private var interruption: Int32?
    private var runner: ShardRunner?

    /// A run of the package at `packageDirectory`, whose run logs and durations live in `repositoryRoot`'s `.swift-sure/`.
    ///
    /// `runToken` is the token every log of this run carries; a fresh one unless a caller needs to know it.
    public init(
        packageDirectory: URL,
        repositoryRoot: URL,
        requestedShards: Int?,
        shardTimeoutSeconds: TimeInterval?,
        performanceCores: Int = TestRunEnvironment.liveHostFacts().performanceCores,
        runToken: String = RunLog.newRunToken()
    ) {
        self.runToken = runToken
        self.packageDirectory = packageDirectory
        self.repositoryRoot = repositoryRoot
        self.requestedShards = requestedShards
        self.shardTimeoutSeconds = shardTimeoutSeconds
        self.performanceCores = performanceCores
    }
}

public extension PackageTestRun {
    /// Builds, lists, runs the shards and answers with the one text to print and the one code to exit with; it never throws.
    ///
    /// **An interrupted run ends every child's session itself before it answers.** The cancellation ends the shards on another thread, one session at a time with a grace each, and the caller exits once this answers, which ends that thread mid-session: a test process that outlived its `SIGTERM` would never be sent the `SIGKILL`. Ending them here, all at once and bounded by the same grace, is what makes the answer's "ended" true.
    func run() -> TestRunResult {
        let result: TestRunResult
        do {
            result = try sequence()
        } catch {
            children.endAll()
            return interruptedResult() ?? TestRunResult(answer: "✘ \(ProductName.current.binary) test — \(error)", exitCode: 1)
        }
        if gate.withLock({ interruption != nil }) {
            children.endAll()
        }
        return result
    }

    /// Ends the run from another thread: the shards first, so ``run()`` answers with what their logs already hold, then every other child this run started.
    func cancel(exitCode: Int32 = 130) {
        gate.lock()
        interruption = exitCode
        let shards = runner
        gate.unlock()
        shards?.cancel()
        children.endAll()
    }
}

private extension PackageTestRun {
    func sequence() throws -> TestRunResult {
        let launcher = RunLauncher(workingDirectory: packageDirectory, repositoryRoot: repositoryRoot, runToken: runToken)
        let started = Date()
        let built = try launcher.run(["swift", "build", "--build-tests"], children: children)
        if let interrupted = interruptedResult() {
            return interrupted
        }
        guard built.exitCode == 0 else {
            let answer = built.filteredAnswer(workingDirectory: packageDirectory)?.text
                ?? "✘ \(ProductName.current.binary) test — swift build --build-tests exited \(built.exitCode)\(built.log.map { " — its log is at \($0.url.path)" } ?? "")"
            return TestRunResult(answer: answer, exitCode: built.exitCode)
        }
        let buildSeconds = Date().timeIntervalSince(started)
        let log = RunLog.open(inDirectory: repositoryRoot, run: runToken)
        let listing = try listTests(loggingTo: log)
        if let interrupted = interruptedResult() {
            return interrupted
        }
        let logged = log.map { " — its log is at \($0.url.path)" } ?? ""
        let tests: [TestIdentifier]
        do {
            tests = try listing.tests.get()
        } catch {
            return TestRunResult(answer: "✘ \(ProductName.current.binary) test — \(error)\(logged).", exitCode: 1)
        }
        guard listing.exitCode == 0, !tests.isEmpty else {
            return TestRunResult(
                answer: "✘ \(ProductName.current.binary) test — swift test list --skip-build \(listing.exitCode == 0 ? "listed no tests" : "exited \(listing.exitCode)"), so there is no expected set to shard\(logged).",
                exitCode: listing.exitCode == 0 ? 1 : listing.exitCode
            )
        }
        var durations = TestDurationStore(repositoryRoot: repositoryRoot)
        let shardCount = requestedShards ?? PackageShardPlanner.defaultShardCount(performanceCores: performanceCores)
        let package = Self.costKeyPath(of: packageDirectory, in: repositoryRoot)
        let secondsPerTest = durations.packageSecondsPerTest(shards: shardCount, package: package)
        let duration: (TestIdentifier) -> Double? = { _ in secondsPerTest }
        let inventory = TestRunEnvironment.liveInventory(repositoryRoot: repositoryRoot)
        let declared = inventory.map(PackageShardPlanner.declared(in:))
        let plan = try Self.confirmingNeverListed(
            PackageShardPlanner.plan(
                tests: tests,
                shards: shardCount,
                displayNames: declared?.displayNames ?? [:],
                conditional: declared?.conditional ?? [],
                package: package,
                history: durations
            ),
            candidates: inventory.map { PackageShardPlanner.neverListed(declaredIn: $0, listed: tests, repositoryRoot: repositoryRoot) } ?? [],
            listed: tests
        ) {
            let log = RunLog.open(inDirectory: repositoryRoot, run: runToken)
            let listing = try listTests(loggingTo: log)
            return Relisting(tests: listing.tests, exitCode: listing.exitCode, logPath: log?.url.path)
        }
        if let interrupted = interruptedResult() {
            return interrupted
        }
        var outcomes = try runShards(plan)
        if let interrupted = interruptedResult(shardsStarted: true, shards: plan.shards.count) {
            return interrupted
        }
        var reconciliation = ShardMerge.reconcile(plan: plan, outcomes: outcomes, shardTimeoutSeconds: shardTimeoutSeconds)
        // A shard that lost tests is explained by its log, so that log is moved out of the next runs' pruning and the answer names where it went.
        let lossy = Set(reconciliation.shards.filter { $0.recording.missing > 0 }.map(\.index))
        if !lossy.isEmpty {
            for (offset, shard) in plan.shards.enumerated() where offset < outcomes.count && lossy.contains(shard.index) {
                outcomes[offset].logPath = RunLog.keep(outcomes[offset].logPath) ?? outcomes[offset].logPath
            }
            reconciliation = ShardMerge.reconcile(plan: plan, outcomes: outcomes, shardTimeoutSeconds: shardTimeoutSeconds)
        }
        if let recording = TestDurationStore.Recording(packageShards: reconciliation.shards, requestedShards: shardCount, package: package) {
            durations.record(recording)
        }
        let rendered = ShardAnswerRenderer(swiftPackage: true).render(reconciliation, plan: plan)
        let notes = [
            "build \(ShardSeconds.text(buildSeconds)) · \(PackageShardPlanner.shardsNote(shards: plan.shards.count, requested: plan.requestedShards, tests: tests))",
            PackageShardPlanner.estimateNote(tests: tests, duration: duration),
        ].compactMap(\.self)
        return TestRunResult(
            answer: ([rendered] + notes).joined(separator: reconciliation.isGreen ? "\n" : "\n\n"),
            exitCode: reconciliation.exitCode,
            reconciled: TestRunResult.Reconciled(isGreen: reconciliation.isGreen, stoppedBySift: outcomes.contains { $0.timedOut }),
            runToken: runToken,
            shards: plan.shards.count,
            failedTests: reconciliation.reportedTestFailures
        )
    }

    /// One `swift test list --skip-build`, logged to `log`, which it closes: the tests it named, or why its output named none, and its exit code.
    func listTests(loggingTo log: RunLog?) throws -> Listing {
        let listing = try Self.standardOutput(of: ["swift", "test", "list", "--skip-build"], in: packageDirectory, children: children, log: log)
        log?.close()
        let text = String(bytes: listing.output, encoding: .utf8) ?? ""
        return Listing(tests: Result { try PackageShardPlanner.listed(text) }, exitCode: listing.exitCode, text: text)
    }

    /// Runs one `swift test --skip-build --ignore-lock --filter` per planned shard, all at once, each bounded on wall clock as a simulator shard is.
    func runShards(_ plan: ShardPlan) throws -> [ShardOutcome] {
        let shards = ShardRunner(workingDirectory: packageDirectory, repositoryRoot: repositoryRoot, children: children, run: runToken)
        gate.lock()
        let cancelled = interruption != nil
        if !cancelled {
            runner = shards
        }
        gate.unlock()
        guard !cancelled else {
            throw TestRunError.interrupted
        }
        let streams = EventStreamDirectory.make(in: repositoryRoot, for: "shard-events")
        defer {
            streams?.remove()
        }
        let assignments = plan.shards.map { shard in
            let stream = streams?.arguments(writing: "shard-\(shard.index).jsonl") ?? []
            return ShardRunner.Assignment(
                index: shard.index,
                argv: ["swift", "test", "--skip-build", "--ignore-lock"] + stream + ["--filter", PackageShardPlanner.filter(for: shard.tests)],
                bound: shardTimeoutSeconds.map { ShardRunner.bound(forPredicted: shard.predictedSeconds, minimumSeconds: $0) }
                    ?? ShardRunner.bound(forPredicted: shard.predictedSeconds)
            )
        }
        var outcomes = shards.run(assignments)
        for (offset, shard) in plan.shards.enumerated() where offset < outcomes.count {
            guard let streams else {
                outcomes[offset].eventStreamAbsence = "this swift test offers no event-stream option"
                continue
            }
            guard let stream = streams.read("shard-\(shard.index).jsonl") else {
                outcomes[offset].eventStreamAbsence = "its event stream was missing or unreadable"
                continue
            }
            let events = ShardEventStream.read(stream)
            if events.declared.isEmpty {
                outcomes[offset].eventStreamAbsence = "its event stream declared no tests"
            } else {
                outcomes[offset].eventStream = events
            }
        }
        return outcomes
    }
}

extension PackageTestRun {
    /// The answer an interrupted run gives, or `nil` where nothing interrupted it.
    ///
    /// Once the shards have started the answer carries a red reconciliation that SwiftSure ended, as an interrupted `swift-sure run -- swift test` files one; before that it carries none, because nothing had tested the tree. It carries the run's token either way, so the logs it left can be named, and `shards` where the plan was already made.
    func interruptedResult(shardsStarted: Bool = false, shards: Int? = nil) -> TestRunResult? {
        gate.lock()
        defer { gate.unlock() }
        return interruption.map {
            TestRunResult(
                answer: "✘ \(ProductName.current.binary) test — \(TestRunError.packageRunInterrupted)",
                exitCode: $0,
                reconciled: shardsStarted ? TestRunResult.Reconciled(isGreen: false, stoppedBySift: true) : nil,
                runToken: runToken,
                shards: shards
            )
        }
    }
}

extension PackageTestRun {
    /// `directory`'s path relative to `root`, or `.` for the root itself and for a directory outside it.
    static func costKeyPath(of directory: URL, in root: URL) -> String {
        let path = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard path != base, path.hasPrefix(base + "/") else {
            return "."
        }
        return String(path.dropFirst(base.count + 1))
    }

    /// One listing run to confirm the never-listed candidates: what it named, or why its output named none, its exit code and its log.
    struct Relisting {
        var tests: Result<[TestIdentifier], any Error>
        var exitCode: Int32
        var logPath: String?
    }

    /// One `swift test list` run: what it named, or why its output named none, its exit code and the text it printed.
    struct Listing {
        var tests: Result<[TestIdentifier], any Error>
        var exitCode: Int32
        var text: String
    }

    /// `plan` owing the never-listed `candidates` that confirmation leaves, each confirming listing of `listed` taken from `relist` with the path of its log.
    ///
    /// A listing that exited non-zero, or whose output could not be read, is a failed one — see ``PackageShardPlanner/confirmed(neverListed:listed:relisting:)`` — however much of it was printed. Where no listing confirmed the candidates, the plan's ``ShardPlan/neverListedNote`` says why, naming the last listing's log, kept out of the next runs' pruning.
    static func confirmingNeverListed(
        _ plan: ShardPlan,
        candidates: [TestIdentifier],
        listed: [TestIdentifier],
        relist: () throws -> Relisting
    ) rethrows -> ShardPlan {
        var plan = plan
        var listings = 0
        var last: Relisting?
        let confirmation = try PackageShardPlanner.confirmed(neverListed: candidates, listed: listed) {
            let relisting = try relist()
            listings += 1
            last = relisting
            return relisting.exitCode == 0 ? try? relisting.tests.get() : nil
        }
        plan.neverListed = confirmation.owed
        if !confirmation.complete, let last {
            let log = last.logPath.map { RunLog.keep($0) ?? $0 }
            let why = if last.exitCode != 0 {
                "the `swift test list` run to confirm them exited \(last.exitCode)\(log.map { " — its log is at \($0)" } ?? "")"
            } else if case .failure = last.tests {
                "the `swift test list` run to confirm them printed a line that names no test\(log.map { " — its log is at \($0)" } ?? "")"
            } else {
                "none of the \(listings) `swift test list` runs to confirm them named every test the first did\(log.map { " — the last one's log is at \($0)" } ?? "")"
            }
            plan.neverListedNote = "none was ruled out: \(why)."
        }
        return plan
    }

    /// Runs `arguments` as one of `children` and answers what it wrote to its standard output alone, both streams going to `log`.
    ///
    /// **Standard output alone is the listing.** SwiftPM writes to standard error whatever it has to say about itself — a wait on another process's `.build` lock is printed with no newline, so read together with the listing it glues itself onto the first test's line — and a listing read from both streams is a listing with a line that names no test.
    static func standardOutput(of arguments: [String], in directory: URL, children: SetAsideChildren, log: RunLog?) throws -> (output: Data, exitCode: Int32) {
        let null = open("/dev/null", O_RDONLY | O_CLOEXEC)
        defer { close(null) }
        let stdout = Pipe()
        let stderr = Pipe()
        let pid: pid_t
        do {
            pid = try children.spawn(
                "/usr/bin/env",
                arguments,
                in: directory,
                environment: ProcessInfo.processInfo.environment,
                streams: SetAsideChildren.Streams(input: null, output: stdout.fileHandleForWriting.fileDescriptor, error: stderr.fileHandleForWriting.fileDescriptor),
                forwardingSignals: true
            )
        } catch {
            ProcessStreams.abandon(stdout, stderr)
            throw error
        }
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        let (output, failure) = ProcessStreams.drain(stdout: stdout, stderr: stderr)
        log?.append(output)
        log?.append(failure)
        return (output, SetAsideChildren.exitCode(waitingFor: pid))
    }
}
