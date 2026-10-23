//
// Copyright © Agulhas Labs
//

import Foundation

/// What a run over several plans has before its shards launch — each plan's `.xctestrun` and the plan made over all of them — and when each was done.
struct MultiPlanPreparation {
    let began: Date
    let built: Date
    let enumerated: Date
    /// Each plan's `.xctestrun`, by plan name.
    let xctestruns: [String: URL]
    /// Every plan the run covers, in order, those that enumerated no tests included.
    let names: [String]
    let plan: MultiPlanShardPlan
    var animationsNote: String?

    /// The run's phases, charged as ``TestRunPreparation/phases(shardsBegan:shardsEnded:tornDown:)`` charges a single plan's.
    func phases(shardsBegan: Date, shardsEnded: Date, tornDown: Date) -> ShardPhases {
        ShardPhases(
            build: built.timeIntervalSince(began),
            enumerate: enumerated.timeIntervalSince(built),
            devicesReady: shardsBegan.timeIntervalSince(enumerated),
            shards: shardsEnded.timeIntervalSince(shardsBegan),
            teardown: tornDown.timeIntervalSince(shardsEnded)
        )
    }
}

extension TestRun {
    /// A run over several plans: one build that names no plan, each plan's own `.xctestrun` and enumeration, one plan over every (plan, test) item, and each device working through its segments.
    ///
    /// **A sanitizer plan is refused** before anything is launched where the plans are known then, and after the build where only its files name them: a sanitizer builds products of its own, which one build shared by every plan cannot give it.
    func multiPlanSequence(prefix: String, sweepLines: [String]) throws -> Result {
        let (invocation, resolution) = try validated()
        let declared = request.allPlans ? schemePlans(of: invocation.scheme) : TestRun.unique(request.plans)
        try refuseSanitized(declared)
        let facts = environment.hostFacts()
        let ledger = try armed(prefix: prefix)
        var durations = TestDurationStore(repositoryRoot: request.repositoryRoot)
        let prepared = try multiPlannedWhileProvisioning(invocation, declared: declared, facts: facts, resolution: resolution, in: ledger) { plans, provisioned in
            MultiPlanShardPlanner.plan(
                plans,
                shards: provisioned,
                overheadSeconds: slimBoots.mode?.isSlim == true ? ShardPlanner.slimOverheadSeconds : ShardPlanner.overheadSeconds,
                duration: { durations.median(for: $0.enumerated) }
            )
        }
        let plan = prepared.plan
        state.deleteSurplus(beyond: plan.shards.count, simctl: environment.simctl, overrides: environment.overrides, leases: environment.leases)
        slimBoots.forget(shardsFrom: plan.shards.count)
        try throwIfInterrupted()
        var notes: [String] = []
        if state.watcherStoppedWatching() == true {
            notes.append(TestRun.watcherAbandonedNote)
        }
        if let animationsNote = prepared.animationsNote {
            notes.append(animationsNote)
        }
        let shardsBegan = environment.now()
        let outcomes = try runLanes(plan, invocation: invocation, xctestruns: prepared.xctestruns, in: ledger)
        let shardsEnded = environment.now()
        try throwIfInterrupted()
        let rendered = mergedPlans(plan, outcomes: outcomes, durations: &durations)
        return merged(rendered, declared: prepared.names, shards: plan.shards.count, sweepLines: sweepLines, notes: notes) {
            prepared.phases(shardsBegan: shardsBegan, shardsEnded: shardsEnded, tornDown: $0)
        }
    }
}

private extension TestRun {
    /// The plans the scheme's test action lists, in its order, or none where the scheme was not read.
    func schemePlans(of scheme: String) -> [String] {
        let references = environment.schemes().schemes.filter { $0.name == scheme }.flatMap { $0.testAction?.planReferences ?? [] }
        return TestRun.unique(references.map(SchemeSurvey.planName(of:)))
    }

    /// Refuses the run where any of `plans` switches on a sanitizer.
    func refuseSanitized(_ plans: [String]) throws {
        guard let (plan, sanitizers) = TestPlanSanitizers.first(among: plans, under: request.workingDirectory) else {
            return
        }
        throw TestRun.refusal(TestRunError.sanitizedPlan(plan: plan, sanitizers: sanitizers), exitCode: TestRun.usageExit)
    }

    /// The one build, each plan's `.xctestrun` and enumeration, and the plan, with this run's devices created and booted beside them, as ``plannedWhileProvisioning(_:shards:facts:resolution:in:plan:)`` does for one plan.
    func multiPlannedWhileProvisioning(
        _ invocation: TestInvocation,
        declared: [String],
        facts: TestRunEnvironment.HostFacts,
        resolution: ShardDevices.Resolution,
        in ledger: ShardLedger,
        plan: ([MultiPlanShardPlanner.PlanTests], Int) -> MultiPlanShardPlan
    ) throws -> MultiPlanPreparation {
        let began = environment.now()
        let provisioned = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            self.provision(requested: self.request.requestedShards, facts: facts, resolution: resolution, invocation: invocation)
            provisioned.signal()
        }
        let enumerated: MultiPlanPreparation.EnumeratedPlans
        do {
            enumerated = try enumeratedPlans(invocation, declared: declared, since: began, in: ledger)
        } catch {
            provisioned.wait()
            try throwIfInterrupted()
            throw error
        }
        provisioned.wait()
        try throwIfInterrupted()
        if let failure = state.provisionFailure {
            throw TestRun.refusal(failure, exitCode: TestRun.failureExit)
        }
        let shardPlan = plan(enumerated.plans, state.udids().count)
        return MultiPlanPreparation(began: began, built: enumerated.built, enumerated: enumerated.enumeratedAt, xctestruns: enumerated.runs, names: enumerated.names, plan: shardPlan, animationsNote: enumerated.note)
    }

    /// Builds once with no plan named, then finds and enumerates each plan's `.xctestrun`, each into files of its own.
    func enumeratedPlans(
        _ invocation: TestInvocation,
        declared: [String],
        since began: Date,
        in ledger: ShardLedger
    ) throws -> MultiPlanPreparation.EnumeratedPlans {
        let built = try build(invocation, in: ledger)
        let (directory, entries) = try productsListing(invocation)
        let written = entries.filter { $0.name.hasSuffix(".xctestrun") && $0.modified >= began }.map(\.name).sorted()
        let names = declared.isEmpty ? TestRun.planNames(in: written, scheme: invocation.scheme) : declared
        guard !names.isEmpty else {
            throw TestRun.refusal(TestRunError.noPlans(written), exitCode: TestRun.usageExit)
        }
        if declared.isEmpty {
            try refuseSanitized(names)
        }
        var plans: [MultiPlanShardPlanner.PlanTests] = []
        var runs: [String: URL] = [:]
        var note: String?
        for name in names {
            let file = try ending(TestRun.usageExit) { try TestInvocation.xctestrunName(among: written, plan: name) }
            let animations = TestRun.animationsDecision(for: directory.appendingPathComponent(file), in: ledger, request: request, environment: environment)
            note = note ?? animations.note
            try throwIfInterrupted()
            let tests = try enumerated(invocation, xctestrun: animations.xctestrun, in: ledger, suffix: "-\(name)")
            runs[name] = animations.xctestrun
            if !tests.isEmpty {
                plans.append(MultiPlanShardPlanner.PlanTests(plan: name, tests: tests))
            }
        }
        state.decidedAnimations(note: note)
        guard !plans.isEmpty else {
            if !invocation.only.isEmpty {
                throw TestRun.refusal(TestInvocationError.onlyEnumeratedNothing(invocation.only), exitCode: TestRun.usageExit)
            }
            throw Ending(text: "✔ \(ProductName.current.binary) test — the plans enumerated no tests, so there was nothing to run", exitCode: 0)
        }
        return MultiPlanPreparation.EnumeratedPlans(built: built, enumeratedAt: environment.now(), plans: plans, runs: runs, names: names, note: note)
    }

    /// Runs every shard's segments on the device provisioned for it, one lane per device, each device deleted as its lane ends unless it is the last to.
    ///
    /// Answers each shard's outcomes in its segments' order, the shards in the plan's order.
    func runLanes(_ plan: MultiPlanShardPlan, invocation: TestInvocation, xctestruns: [String: URL], in ledger: ShardLedger) throws -> [[ShardOutcome]] {
        let shards = try readiedRunner(devices: plan.shards.count, in: ledger)
        let lanes = zip(plan.shards, state.udids()).map { shard, udid in
            PlanLanes.Lane(index: shard.index, udid: udid, segments: shard.segments.compactMap { segment in
                xctestruns[segment.plan].map { xctestrun in
                    ShardRunner.Assignment(
                        index: shard.index,
                        argv: invocation.shardArguments(
                            xctestrun: xctestrun,
                            deviceUDID: udid,
                            tests: segment.tests,
                            resultBundle: ledger.directory.appendingPathComponent("\(shard.index)-\(segment.plan).xcresult")
                        ),
                        bound: request.shardTimeoutSeconds.map { ShardRunner.bound(forPredicted: segment.predictedSeconds, minimumSeconds: $0) }
                            ?? ShardRunner.bound(forPredicted: segment.predictedSeconds),
                        silence: ShardRunner.silenceBound(forLongestTest: segment.longestTestSeconds)
                    )
                }
            })
        }
        let environment = environment
        let state = state
        return PlanLanes(shards: shards, stopped: { state.isCancelled }).run(lanes) { lane in
            state.deleteEnded(udid: lane.udid, simctl: environment.simctl, overrides: environment.overrides, leases: environment.leases)
        }
    }

    /// Each plan reconciled on its own against its segments, in the order the plan's shards run them, and its timings kept.
    func mergedPlans(_ plan: MultiPlanShardPlan, outcomes: [[ShardOutcome]], durations: inout TestDurationStore) -> [MultiPlanPreparation.ReconciledPlan] {
        let inventory = environment.declaredInventory()
        return plan.plans.map { name in
            let projected = plan.projected(plan: name, displayNames: inventory?.displayNames ?? [:], conditional: inventory?.conditionalTests ?? [])
            let planOutcomes = zip(plan.shards, outcomes).compactMap { shard, lane in
                shard.segments.firstIndex { $0.plan == name }.flatMap { lane.indices.contains($0) ? lane[$0] : nil }
            }
            let reconciliation = ShardMerge.reconcile(plan: projected, outcomes: planOutcomes, shardTimeoutSeconds: request.shardTimeoutSeconds)
            for shard in projected.shards {
                if let recording = reconciliation.recording(forShard: shard.index) {
                    durations.record(recording)
                }
            }
            return MultiPlanPreparation.ReconciledPlan(name: name, plan: projected, reconciliation: reconciliation)
        }
    }

    /// The answer over every plan: one verdict, each plan's line and the run's timing, devices and housekeeping once, and the first failing plan's exit code.
    func merged(
        _ plans: [MultiPlanPreparation.ReconciledPlan],
        declared: [String],
        shards: Int,
        sweepLines: [String],
        notes: [String],
        phases: (Date) -> ShardPhases
    ) -> Result {
        let cleanup = state.teardown(children: children, simctl: environment.simctl, overrides: environment.overrides, leases: environment.leases, releasingWatcher: false)
        var notes = notes
        if state.watcherStoppedWatching() == true, !notes.contains(TestRun.watcherAbandonedNote) {
            notes.append(TestRun.watcherAbandonedNote)
        }
        let phases = phases(environment.now())
        let failingNames = plans.filter { !$0.reconciliation.failed.isEmpty }.map(\.name)
        let renderer = ShardAnswerRenderer(
            phases: phases,
            derivedDataLine: request.derivedDataPath.map(WorktreeDerivedData.line(for:)),
            devicesLine: cleanup?.summary(bootClause: ShardBootLine.clause(mode: slimBoots.mode, shards: slimBoots.shards, retriedRead: slimBoots.retriedRead)),
            crashReports: environment.crashReports(beganAt),
            sweepLines: sweepLines,
            rerunCommand: request.rerunCommandPrefix(plans: failingNames, allPlans: false), rerunSuffix: request.rerunCommandSuffix,
            bootedSlim: ShardBootLine.bootedSlim(mode: slimBoots.mode, shards: slimBoots.shards)
        )
        let answers = plans.map { ShardAnswerRenderer.PlanAnswer(name: $0.name, plan: $0.plan, reconciliation: $0.reconciliation) }
        let answer = ([renderer.render(plans: answers, declared: declared, shards: shards)] + notes).joined(separator: "\n\n")
        _ = state.teardown(children: children, simctl: environment.simctl, overrides: environment.overrides, leases: environment.leases, releasingWatcher: true)
        let failing = plans.first { $0.reconciliation.exitCode != 0 }
        return Result(answer: answer, exitCode: failing?.reconciliation.exitCode ?? 0, failedTests: plans.contains { $0.reconciliation.reportedTestFailures != nil } ? plans.flatMap { $0.reconciliation.reportedTestFailures ?? [] } : nil)
    }
}

extension MultiPlanPreparation {
    /// What the one build and each plan's enumeration came to, before the plan is made.
    struct EnumeratedPlans {
        let built: Date
        let enumeratedAt: Date
        let plans: [MultiPlanShardPlanner.PlanTests]
        let runs: [String: URL]
        let names: [String]
        let note: String?
    }

    /// One plan's reconciliation, against that plan's own segments.
    struct ReconciledPlan {
        let name: String
        let plan: ShardPlan
        let reconciliation: ShardReconciliation
    }
}

extension TestRun {
    /// `names` with each kept once, where it first appears.
    static func unique(_ names: [String]) -> [String] {
        var kept: [String] = []
        for name in names where !kept.contains(name) {
            kept.append(name)
        }
        return kept
    }

    /// The plans a build that named none wrote files for, read off the names `<scheme>_<plan>_<platform>.xctestrun`, in name order.
    static func planNames(in written: [String], scheme: String) -> [String] {
        written.compactMap { name in
            guard name.hasPrefix("\(scheme)_"), name.hasSuffix(".xctestrun") else {
                return nil
            }
            let middle = name.dropFirst(scheme.count + 1).dropLast(".xctestrun".count)
            guard let platform = platformSeparator(in: middle) else {
                return nil
            }
            return String(middle[..<platform])
        }
    }

    /// The `_` before the SDK component (`iphonesimulator27.0-arm64`, `macosx15.0-undefined_arch`): the last whose tail is letters then a digit, so an architecture spelled `undefined_arch` is not taken for it.
    private static func platformSeparator(in middle: Substring) -> Substring.Index? {
        middle.indices.reversed().first { index in
            guard middle[index] == "_" else {
                return false
            }
            let start = middle.index(after: index)
            let tail = middle[start...].drop { $0.isLetter }
            return tail.first?.isNumber == true && tail.startIndex > start
        }
    }
}
