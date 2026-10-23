//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Pins the leases a sharded run holds on the devices it creates, in a scratch store through an injected `simctl` — no test here touches a real device or the machine's own lease store.
@Suite(.temporaryDirectories)
struct ShardLeaseTests {
    /// Every shard device is leased to this process while the shards run, as a created device, and no lease outlives the run.
    @Test
    func everyShardDeviceIsLeasedWhileTheRunRunsAndNoneAfterIt() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        let seen = Seen<[LeaseStore.Entry]>()
        var fake = Fake(root: root, leases: leases)
        fake.whileBooting = { seen.take(leases.store.all()) }

        _ = TestRun(request: Self.request(in: root), environment: fake.environment()).run()
        let atBoot = try #require(seen.first())

        #expect(atBoot.map(\.udid) == Fake.udids.sorted())
        #expect(atBoot.allSatisfy { $0.lease.holderPID == getpid() && $0.lease.createdDevice && $0.lease.clonedFrom == nil })
        #expect(leases.store.all().isEmpty)
    }

    /// An interrupted run gives up every lease along with the devices its teardown deleted.
    @Test
    func anInterruptedRunLeavesNoLease() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        let holder = Holder()
        let seen = Seen<[LeaseStore.Entry]>()
        var fake = Fake(root: root, leases: leases)
        fake.whileRunning = {
            seen.take(leases.store.all())
            let cancelled = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                holder.run?.cancel(exitCode: 130)
                cancelled.signal()
            }
            cancelled.wait()
        }
        let run = TestRun(request: Self.request(in: root), environment: fake.environment())
        holder.run = run

        let result = run.run()

        #expect(result.exitCode == 130)
        #expect(try !#require(seen.first()).isEmpty)
        #expect(leases.store.all().isEmpty)
    }

    /// A device whose delete failed keeps its lease, so no other tool takes a half-deleted device; the one that went gives its lease up.
    @Test
    func aFailedDeleteKeepsItsLease() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        var fake = Fake(root: root, leases: leases)
        fake.failingDeletes = [Fake.udids[0]]

        let result = TestRun(request: Self.request(in: root), environment: fake.environment()).run()

        #expect(result.answer.contains("1 left: \(Fake.udids[0])"))
        #expect(leases.store.all().map(\.udid) == [Fake.udids[0]])
    }

    /// The sweep leaves a dead run's device alone while another live process holds a lease on it, says so, and keeps the record; a device whose holder is gone is deleted and its lease given up.
    @Test
    func theSweepSkipsADeviceALiveHolderLeasesAndDeletesOneWhoseHolderIsGone() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        let held = Fake.udids[0]
        let abandoned = Fake.udids[1]
        let ledger = try Self.deadLedger(in: root, udids: [held, abandoned])
        let live = getppid()
        _ = try leases.store.acquire(udid: held, ttl: 600, holderPID: live, now: Date())
        _ = try leases.store.acquire(udid: abandoned, ttl: 600, holderPID: Self.exitedPID(), now: Date(), createdDevice: true, token: ShardLeases.token(for: abandoned))
        let deletes = Seen<String>()

        let report = ShardSweep.sweep(repositoryRoot: root, prefix: Self.prefix, leases: leases, run: { _, arguments in
            if arguments.contains("delete") {
                deletes.take(arguments.last ?? "")
            }
            return Subprocess.Output(succeeded: true, standardOutput: arguments.contains("list") ? #"{ "devices": {} }"# : "")
        }, started: { _ in nil })

        #expect(deletes.all() == [abandoned])
        #expect(report.sentences.contains("skipped \(held) left by run \(Self.deadRun): leased by pid \(live)"))
        #expect(leases.store.all().map(\.udid) == [held])
        #expect(FileManager.default.fileExists(atPath: ledger.fileURL.path))
    }

    /// A lease carrying the run's own token for the device is the dead run's, whichever live process now has the pid it named: the sweep deletes the device and gives the lease up.
    @Test
    func aLeaseCarryingTheRunsOwnTokenIsNeverForeign() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        let device = Fake.udids[0]
        _ = try Self.deadLedger(in: root, udids: [device])
        _ = try leases.store.acquire(udid: device, ttl: 600, holderPID: getppid(), now: Date(), createdDevice: true, token: ShardLeases.token(for: device))
        let deletes = Seen<String>()

        let report = Self.sweep(root, leases: leases, deletes: deletes)

        #expect(deletes.all() == [device])
        #expect(!report.sentences.contains { $0.hasPrefix("skipped") })
        #expect(leases.store.all().isEmpty)
    }

    /// A lease file that cannot be read is held, as the store treats it: the sweep skips the device, says why and keeps the record.
    @Test
    func theSweepSkipsADeviceWhoseLeaseCannotBeRead() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        let device = Fake.udids[0]
        let ledger = try Self.deadLedger(in: root, udids: [device])
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        try Data("not a lease".utf8).write(to: leases.store.url(for: device))
        let deletes = Seen<String>()

        let report = Self.sweep(root, leases: leases, deletes: deletes)

        #expect(deletes.all().isEmpty)
        #expect(report.sentences == ["skipped \(device) left by run \(Self.deadRun): its lease cannot be read"])
        #expect(FileManager.default.fileExists(atPath: ledger.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: leases.store.url(for: device).path))
    }

    /// A surplus device's delete gives its lease up along with it.
    @Test
    func deletingSurplusDevicesGivesTheirLeasesUp() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        let ledger = try Self.deadLedger(in: root, udids: Fake.udids)
        for udid in Fake.udids {
            #expect(leases.take(udid: udid) == nil)
        }
        let state = TestRun.State()
        state.began(with: ledger)

        state.deleteSurplus(beyond: 1, simctl: { _, _ in Subprocess.Output(succeeded: true, standardOutput: "") }, overrides: DisabledServicesOverride(root: root.appendingPathComponent("var-tmp")), leases: leases)

        #expect(leases.store.all().map(\.udid) == [Fake.udids[0]])
    }

    /// A device somebody else already leases when the run creates it counts as a lease failure like any other: the run goes on and the devices line says so once.
    @Test
    func aDeviceAlreadyLeasedAtCreateTimeLeavesTheRunGoingAndSaysSoOnce() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        for udid in Fake.udids {
            _ = try leases.store.acquire(udid: udid, ttl: 600, holderPID: getppid(), now: Date())
        }
        let unleased = TestRun(request: Self.request(in: root), environment: Fake(root: root, leases: nil).environment()).run()

        let result = TestRun(request: Self.request(in: root), environment: Fake(root: root, leases: leases).environment()).run()

        #expect(result.exitCode == unleased.exitCode)
        #expect(result.answer.components(separatedBy: "; not leased: ").count == 2)
    }

    /// A delete that went through leaves a lease carrying some other token alone.
    @Test
    func releasingADeletedDeviceLeavesAnotherTokensLeaseAlone() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        let device = Fake.udids[0]
        _ = try leases.store.acquire(udid: device, ttl: 600, holderPID: getppid(), now: Date(), token: "someone-else")

        let deletion = ShardDevices.delete(udid: device, leases: leases, run: { _, _ in Subprocess.Output(succeeded: true, standardOutput: "") })

        #expect(deletion.failure == nil)
        #expect(leases.store.all().map(\.lease.token) == ["someone-else"])
    }

    /// The watcher that deletes a dead owner's devices gives their leases up too.
    @Test
    func theWatcherGivesUpTheLeasesOfTheDevicesItDeletes() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let leases = ShardLeases(directory: root.appendingPathComponent("leases"))
        _ = try Self.deadLedger(in: root, udids: Fake.udids)
        for udid in Fake.udids {
            #expect(leases.take(udid: udid) == nil)
        }

        let status = ShardGuardian.sweep(
            read: nil,
            runID: Self.deadRun,
            repositoryRoot: root,
            leases: leases,
            run: { _, _ in Subprocess.Output(succeeded: true, standardOutput: "") },
            endSessions: { _ in }
        )

        #expect(status == 0)
        #expect(leases.store.all().isEmpty)
    }

    /// A store that cannot be written fails nothing — the run ends as the same run with no store at all does — and the devices line says why once.
    @Test
    func anUnwritableStoreLeavesTheRunGreenAndSaysSoOnce() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let blocker = root.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let leases = ShardLeases(directory: blocker.appendingPathComponent("leases"))

        let result = TestRun(request: Self.request(in: root), environment: Fake(root: root, leases: leases).environment()).run()
        let unleased = TestRun(request: Self.request(in: root), environment: Fake(root: root, leases: nil).environment()).run()

        #expect(result.exitCode == unleased.exitCode)
        #expect(!unleased.answer.contains("not leased"))
        #expect(result.answer.components(separatedBy: "; not leased: the lease store at ").count == 2)
    }

    /// The live run leases into `.simwalk/leases` under the account's home, the machine's shared store.
    @Test
    func theLiveRunLeasesIntoTheAccountsSimwalkStore() throws {
        let root = try TemporaryDirectory.make("shard-lease")
        let home = try String(cString: #require(getpwuid(getuid())).pointee.pw_dir)

        let live = TestRunEnvironment.live(for: Self.request(in: root), children: SetAsideChildren())

        #expect(ShardLeases.sharedDirectory.path == "\(home)/.simwalk/leases")
        #expect(live.leases?.directory.path == "\(home)/.simwalk/leases")
    }
}

private extension ShardLeaseTests {
    static var prefix: String {
        "a1b2c3"
    }

    static var deadRun: String {
        "0f9e8d7c"
    }

    static func request(in root: URL) -> TestRunRequest {
        TestRunRequest(
            scheme: "TestDemo",
            deviceTypeName: "iPhone 17",
            requestedShards: 2,
            workingDirectory: root,
            repositoryRoot: root,
            executable: root.appendingPathComponent("swift-sure")
        )
    }

    /// The record of a run whose owner is gone, naming those udids.
    @discardableResult
    static func deadLedger(in root: URL, udids: [String]) throws -> ShardLedger {
        var ledger = try ShardLedger(repositoryRoot: root, runID: deadRun, prefix: prefix, owner: ShardLedger.Identity(pid: 4711, startMicroseconds: 111), started: { _ in nil })
        for (index, udid) in udids.enumerated() {
            try ledger.recordIntent(shard: index)
            try ledger.record(udid: udid, forShard: index)
        }
        return ledger
    }

    /// The sweep of the dead run's devices in `root`, recording the udids it deleted.
    static func sweep(_ root: URL, leases: ShardLeases, deletes: Seen<String>) -> ShardSweep.Report {
        ShardSweep.sweep(repositoryRoot: root, prefix: prefix, leases: leases, run: { _, arguments in
            if arguments.contains("delete") {
                deletes.take(arguments.last ?? "")
            }
            return Subprocess.Output(succeeded: true, standardOutput: arguments.contains("list") ? #"{ "devices": {} }"# : "")
        }, started: { _ in nil })
    }

    /// The pid of a process this test started and saw exit, which is a holder that is gone.
    static func exitedPID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    /// What a seam saw of the store, in the order it looked.
    final class Seen<Look>: @unchecked Sendable {
        private let gate = NSLock()
        private var looks: [Look] = []

        func take(_ look: Look) {
            gate.withLock { looks.append(look) }
        }

        func first() -> Look? {
            gate.withLock { looks.first }
        }

        func all() -> [Look] {
            gate.withLock { looks }
        }
    }

    /// The run a cancelling seam reaches, which does not exist yet when its environment is built.
    final class Holder: @unchecked Sendable {
        private let gate = NSLock()
        private var held: TestRun?

        var run: TestRun? {
            get { gate.withLock { held } }
            set { gate.withLock { held = newValue } }
        }
    }

    /// Every seam a run reaches for, answered from memory.
    struct Fake {
        let root: URL
        let leases: ShardLeases?
        var failingDeletes: [String] = []
        var whileBooting: (@Sendable () -> Void)?
        var whileRunning: (@Sendable () -> Void)?

        static var udids: [String] {
            ["11111111-2222-3333-4444-555555555555", "66666666-7777-8888-9999-000000000000"]
        }

        static var moment: Date {
            Date(timeIntervalSince1970: 1_000_000)
        }

        static var xctestrunName: String {
            "TestDemo_Default_iphonesimulator27.0-arm64.xctestrun"
        }

        func environment() -> TestRunEnvironment {
            let products = root.appendingPathComponent("Build/Products")
            let settings: TestRunEnvironment.Launch = { _ in
                TestRunEnvironment.Launched(exitCode: 0, answer: "", output: Data(#"[{ "buildSettings": { "BUILD_DIR": "\#(products.path)" } }]"#.utf8))
            }
            let whileRunning = whileRunning
            return TestRunEnvironment(
                simctl: simctl(),
                launch: { arguments in
                    if arguments.contains("-showBuildSettings") {
                        return try settings(arguments)
                    }
                    if let flag = arguments.firstIndex(of: "-test-enumeration-output-path"), flag + 1 < arguments.count {
                        let document = #"{ "values": [{ "testPlan": "Default", "enabledTests": [{ "identifier": "GizmoTests/T/t1()" }, { "identifier": "GizmoTests/T/t2()" }] }] }"#
                        try Data(document.utf8).write(to: URL(fileURLWithPath: arguments[flag + 1]))
                    }
                    return TestRunEnvironment.Launched(exitCode: 0, answer: "")
                },
                buildSettings: settings,
                armWatcher: { _, _, _ in
                    TestRunEnvironment.Watcher(identity: ShardLedger.Identity(pid: 4711, startMicroseconds: 111), watching: { true }, release: { true })
                },
                shardRunner: { _ in
                    TestRunEnvironment.Shards(
                        run: { assignments in
                            guard let whileRunning else {
                                return assignments.map { _ in ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 0, wallSeconds: 1, logPath: "/dev/null") }
                            }
                            whileRunning()
                            return []
                        },
                        cancel: {}
                    )
                },
                listDirectory: { _ in [TestRunEnvironment.Entry(name: Fake.xctestrunName, modified: Fake.moment)] },
                hostFacts: { TestRunEnvironment.HostFacts(performanceCores: 8, memoryGB: 32) },
                crashReports: { _ in [] },
                now: { Fake.moment },
                overrides: DisabledServicesOverride(root: root.appendingPathComponent("var-tmp")),
                leases: leases
            )
        }

        func simctl() -> @Sendable (String, [String]) throws -> Subprocess.Output {
            let created = Seen<String>()
            let failingDeletes = failingDeletes
            let whileBooting = whileBooting
            return { _, arguments in
                switch arguments.dropFirst().first {
                case "list" where arguments.contains("devicetypes"):
                    return Subprocess.Output(succeeded: true, standardOutput: Fake.catalogue)
                case "list":
                    return Subprocess.Output(succeeded: true, standardOutput: #"{ "devices": {} }"#)
                case "create":
                    let index = created.all().count
                    created.take(Fake.udids[index])
                    return Subprocess.Output(succeeded: true, standardOutput: Fake.udids[index])
                case "boot":
                    whileBooting?()
                    return Subprocess.Output(succeeded: true, standardOutput: "")
                case "delete" where failingDeletes.contains(arguments.last ?? ""):
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "An error was encountered processing the command")
                default:
                    return Subprocess.Output(succeeded: true, standardOutput: "")
                }
            }
        }

        /// What `simctl list devicetypes runtimes -j` prints, cut to the one device type and runtime a resolution needs.
        static var catalogue: String {
            """
            {
              "devicetypes": [{ "name": "iPhone 17", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17" }],
              "runtimes": [{
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": true, "platform": "iOS",
                "supportedDeviceTypes": [{ "name": "iPhone 17", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17" }]
              }]
            }
            """
        }
    }
}
