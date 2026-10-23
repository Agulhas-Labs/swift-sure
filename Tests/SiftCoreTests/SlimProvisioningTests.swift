//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Covers how a sharded run boots: the decision before the first create, the override written between a create and a boot, and the read-back after it, every `simctl` and `xcodebuild` answered from memory.
@Suite(.temporaryDirectories)
struct SlimProvisioningTests {
    // MARK: - The decision

    /// `--stock` never runs the settings read and writes nothing.
    @Test
    func stockRequestedReadsNothingAndWritesNothing() throws {
        var fixture = try Fixture()
        fixture.stock = true

        let run = fixture.run()

        #expect(run.record.mode == .stock(.requested))
        #expect(run.log.count(of: "settings read") == 0)
        #expect(try fixture.overridden() == [])
    }

    /// A runtime with no profile boots stock without reading the settings.
    @Test
    func noProfileReadsNothingAndWritesNothing() throws {
        var fixture = try Fixture()
        fixture.profile = nil

        let run = fixture.run()

        #expect(run.record.mode == .stock(.noProfile(osVersion: "27.0")))
        #expect(run.log.count(of: "settings read") == 0)
        #expect(try fixture.overridden() == [])
    }

    /// Settings that cannot be read boot stock with the first line of what the read said, and write nothing.
    @Test
    func unreadableSettingsBootStock() throws {
        var fixture = try Fixture()
        fixture.settings = TestRunEnvironment.Launched(exitCode: 1, answer: "xcodebuild: error: no scheme\nsecond line", output: Data())

        let run = fixture.run()

        #expect(run.record.mode == .stock(.unreadable("the build settings could not be read: xcodebuild: error: no scheme")))
        #expect(try fixture.overridden() == [])
    }

    /// A read that passed its bound says so, rather than naming a signal.
    @Test
    func aSettingsReadThatTimedOutNamesItsBound() throws {
        var fixture = try Fixture()
        fixture.settings = TestRunEnvironment.Launched(exitCode: 1, answer: "the spawn timed out: env did not finish within 60 s and was ended", output: Data())

        let run = fixture.run()

        #expect(run.record.mode == .stock(.unreadable("the build settings read passed its 60 s bound")))
    }

    /// A failed read quotes the error line, not the log line `xcodebuild` printed before it.
    @Test
    func aFailedReadQuotesTheErrorLineNotTheLogLine() throws {
        var fixture = try Fixture()
        let log = "2026-10-18 11:11:24.980 xcodebuild[58368:48138172] Writing error result bundle to /var/folders/gizmo/Gizmo.xcresult"
        fixture.reads = [TestRunEnvironment.Launched(exitCode: 70, answer: "\(log)\n  xcodebuild: error: Unable to find a destination matching Gizmo\nmore")]

        let run = fixture.run()

        #expect(run.record.mode == .stock(.unreadable("the build settings could not be read: xcodebuild: error: Unable to find a destination matching Gizmo")))
    }

    /// A read that printed only the log line says it printed no error line.
    @Test
    func aReadThatPrintedOnlyTheLogLineSaysSo() throws {
        var fixture = try Fixture()
        fixture.reads = [TestRunEnvironment.Launched(exitCode: 70, answer: "2026-10-18 11:11:24.980 xcodebuild[58368:48138172] Writing error result bundle to /var/folders/gizmo/Gizmo.xcresult\n")]

        let run = fixture.run()

        #expect(run.record.mode == .stock(.unreadable("the build settings could not be read: it printed no error line")))
    }

    /// With no error line, the first line that is not the log line is quoted.
    @Test
    func aReadWithNoErrorLineQuotesTheFirstOtherLine() throws {
        var fixture = try Fixture()
        fixture.reads = [TestRunEnvironment.Launched(exitCode: 70, answer: "2026-10-18 11:11:24.980 xcodebuild[58368:48138172] Writing result bundle\nGizmo could not be opened")]

        let run = fixture.run()

        #expect(run.record.mode == .stock(.unreadable("the build settings could not be read: Gizmo could not be opened")))
    }

    /// A failed read is read once more, and the run goes on from the second read with the first failure on the record.
    @Test
    func aFailedReadIsRetriedAndTheSecondDecides() throws {
        var fixture = try Fixture()
        fixture.reads = [TestRunEnvironment.Launched(exitCode: 70, answer: "xcodebuild: error: transient"), Fixture.settings([:])]

        let run = fixture.run()

        guard case .slim = run.record.mode else {
            Issue.record("expected a slim boot, got \(String(describing: run.record.mode))")
            return
        }

        #expect(run.log.count(of: "settings read") == 2)
        #expect(run.record.retriedRead == "xcodebuild: error: transient")
        #expect(run.answer.contains("(the first build settings read failed: xcodebuild: error: transient; the second worked)"))
    }

    /// Two failed reads boot stock with the second read's line.
    @Test
    func twoFailedReadsBootStockWithTheSecondLine() throws {
        var fixture = try Fixture()
        fixture.reads = [
            TestRunEnvironment.Launched(exitCode: 70, answer: "xcodebuild: error: first"),
            TestRunEnvironment.Launched(exitCode: 70, answer: "xcodebuild: error: second"),
        ]

        let run = fixture.run()

        #expect(run.log.count(of: "settings read") == 2)
        #expect(run.record.mode == .stock(.unreadable("the build settings could not be read: xcodebuild: error: second (the first read failed: xcodebuild: error: first)")))
        #expect(run.record.retriedRead == nil)
    }

    /// A read that timed out is not read again.
    @Test
    func aTimedOutReadIsNotRetried() throws {
        var fixture = try Fixture()
        fixture.reads = [TestRunEnvironment.Launched(exitCode: 1, answer: "the spawn timed out: env did not finish within 60 s and was ended"), Fixture.settings([:])]

        let run = fixture.run()

        #expect(run.log.count(of: "settings read") == 1)
        #expect(run.record.mode == .stock(.unreadable("the build settings read passed its 60 s bound")))
    }

    /// A declaration no rule accounts for boots stock and writes nothing.
    @Test
    func unmappedDeclarationsBootStock() throws {
        var fixture = try Fixture()
        fixture.settings = Fixture.settings(["INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "Gizmo locates."])

        let run = fixture.run()

        #expect(run.record.mode == .stock(.unmapped(["NSLocationWhenInUseUsageDescription"])))
        #expect(try fixture.overridden() == [])
    }

    // MARK: - The override

    /// Each device's override holds exactly the plan's disabled labels, and is there by the time that device boots — written after the create that named it and before its boot — and gone with the device once the run has torn down.
    @Test
    func theOverrideIsWrittenBetweenTheCreateAndTheBoot() throws {
        let fixture = try Fixture()

        let run = fixture.run()

        guard case let .slim(boot) = run.record.mode else {
            Issue.record("expected slim, got \(String(describing: run.record.mode))")
            return
        }
        #expect(boot.plan.disabled == ["com.gizmo.a", "com.gizmo.b", "com.gizmo.c"])
        let events = run.log.taken()
        let lastCreate = try #require(events.lastIndex { $0.hasPrefix("create ") })
        for udid in Fixture.udids {
            let booted = try #require(events.firstIndex { $0.hasPrefix("boot \(udid)") })
            #expect(lastCreate < booted)
            #expect(events[booted] == "boot \(udid) with com.gizmo.a,com.gizmo.b,com.gizmo.c")
        }
        #expect(try fixture.overridden() == [])
    }

    /// An override that cannot be written leaves that shard not slim, with the reason, and the run goes on and never reads that shard back.
    @Test
    func aFailedWriteIsNotSlimAndTheRunGoesOn() throws {
        var fixture = try Fixture()
        let blocker = fixture.root.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        fixture.overridesRoot = blocker.appendingPathComponent("under-a-file")

        let run = fixture.run()

        let outcome = try #require(run.record.shards[0])

        guard case let .notSlim(reason) = outcome else {
            Issue.record("expected not slim, got \(outcome)")
            return
        }

        #expect(reason.hasPrefix("the override could not be written: "))
        #expect(run.log.count(of: "read-back") == 0)
        #expect(run.log.count(of: "boot ") == 2)
    }

    // MARK: - The read-back

    /// Every written label listed as disabled is a slim shard.
    @Test
    func everyLabelReadBackIsSlim() throws {
        let run = try Fixture().run()

        #expect(run.record.shards == [0: .slim, 1: .slim])
        #expect(run.log.count(of: "read-back") == 2)
    }

    /// A shard missing some written labels from the list ran without the override, and says how many were read back.
    @Test
    func labelsMissingFromTheReadBackAreNotSlim() throws {
        var fixture = try Fixture()
        fixture.printDisabled = Fixture.listing(["com.gizmo.a"])

        let run = fixture.run()

        let reason = "the runtime did not apply the override (1 of 3 read back)"

        #expect(run.record.shards == [0: .notSlim(reason), 1: .notSlim(reason)])
    }

    /// A read-back that fails leaves the shard unverified, with the reason, and the run green.
    @Test
    func aFailedReadBackIsUnverified() throws {
        var fixture = try Fixture()
        fixture.readBack = Subprocess.Output(succeeded: false, standardOutput: "", standardError: "boom")

        let run = fixture.run()

        #expect(run.record.shards == [0: .unverified("the read-back failed: boom"), 1: .unverified("the read-back failed: boom")])
    }

    /// A read-back that passes its bound says it timed out.
    @Test
    func aReadBackThatTimedOutIsUnverified() throws {
        var fixture = try Fixture()
        fixture.readBack = Subprocess.Output(succeeded: false, standardOutput: "", standardError: "the spawn timed out: xcrun did not finish within 20 s and was ended")

        let run = fixture.run()

        #expect(run.record.shards == [0: .unverified("the read-back timed out"), 1: .unverified("the read-back timed out")])
    }

    /// The read-back is a `spawn`, and `spawn` is bounded at twenty seconds.
    @Test
    func theReadBackGetsTwentySeconds() {
        #expect(ShardDevices.deadline(of: ["simctl", "spawn", "udid", "launchctl", "print-disabled", "system"]) == 20)
        #expect(ShardDevices.deadline(of: ["simctl", "boot", "udid"]) == 180)
    }

    /// A shard booted stock has no read-back and no outcome.
    @Test
    func aStockRunReadsNothingBack() throws {
        var fixture = try Fixture()
        fixture.stock = true

        let run = fixture.run()

        #expect(run.record.shards.isEmpty)
        #expect(run.log.count(of: "read-back") == 0)
    }

    // MARK: - The answer

    /// A slim run's devices line carries the boot clause, and its failed re-run says that `--stock` rules the slim boot out.
    @Test
    func aFailedSlimRunSaysHowItBootedAndHowToRuleItOut() throws {
        var fixture = try Fixture()
        fixture.failing = true

        let answer = fixture.run().answer

        #expect(answer.contains("2 simulators created, 2 deleted · slim: 3 of 4 services off (iOS 27.0, profile v1), kept for the project: nothing"))
        let lines = answer.components(separatedBy: "\n")
        let rerun = try #require(lines.firstIndex { $0.hasPrefix("  swift-sure test --scheme Gizmo") })
        #expect(lines[rerun + 1] == "  add --stock to rule the slim boot out")
    }

    /// A stock run's devices line says why, and its re-run offers no `--stock`.
    @Test
    func aFailedStockRunSaysWhyAndOffersNoStockFlag() throws {
        var fixture = try Fixture()
        fixture.failing = true
        fixture.stock = true

        let answer = fixture.run().answer

        #expect(answer.contains("2 simulators created, 2 deleted · stock: --stock"))
        #expect(!answer.contains("add --stock"))
    }
}

private extension SlimProvisioningTests {
    /// What one run left behind: its event log and the record of how it booted.
    struct Ran {
        let log: Log
        let record: SlimBootRecord
        let answer: String
    }

    /// An event log the boot threads append to side by side.
    final class Log: @unchecked Sendable {
        private let gate = NSLock()
        private var events: [String] = []
        private var created = 0

        func append(_ event: String) {
            gate.withLock { events.append(event) }
        }

        func taken() -> [String] {
            gate.withLock { events }
        }

        func count(of prefix: String) -> Int {
            taken().filter { $0.hasPrefix(prefix) }.count
        }

        func nextUdid(from udids: [String]) -> String {
            gate.withLock {
                defer { created += 1 }
                return udids[created]
            }
        }
    }

    /// A full sharded run on fakes, with the dials a test turns.
    struct Fixture {
        static let udids = ["11111111-2222-3333-4444-555555555555", "66666666-7777-8888-9999-000000000000"]

        let root: URL
        var overridesRoot: URL
        var stock = false
        var profile: ServiceProfile? = Fixture.profile
        var settings = Fixture.settings([:])
        var reads: [TestRunEnvironment.Launched] = []
        var printDisabled = Fixture.listing(["com.gizmo.a", "com.gizmo.b", "com.gizmo.c"])
        var readBack: Subprocess.Output?
        var failing = false

        init() throws {
            root = try TemporaryDirectory.make("slim-provisioning")
            overridesRoot = root.appendingPathComponent("var-tmp")
        }

        /// The udids whose override file exists under the overrides root.
        func overridden() throws -> Set<String> {
            let overrides = DisabledServicesOverride(root: overridesRoot)
            return try Set(Self.udids.filter { try !overrides.labels(for: $0).isEmpty })
        }

        func run() -> Ran {
            let log = Log()
            let request = TestRunRequest(
                scheme: "Gizmo",
                deviceTypeName: "iPhone 17",
                requestedShards: 2,
                workingDirectory: root,
                repositoryRoot: root,
                executable: root.appendingPathComponent("swift-sure"),
                stock: stock
            )
            let run = TestRun(request: request, environment: environment(log))
            let result = run.run()
            return Ran(log: log, record: run.slimBoots, answer: result.answer)
        }

        func environment(_ log: Log) -> TestRunEnvironment {
            let products = root.appendingPathComponent("Build/Products")
            let overrides = DisabledServicesOverride(root: overridesRoot)
            let profile = profile
            let settings = settings
            let reads = reads
            let listing = printDisabled
            let readBack = readBack
            let failing = failing
            return TestRunEnvironment(
                simctl: { _, arguments in
                    switch arguments.dropFirst().first {
                    case "list" where arguments.contains("devicetypes"):
                        return Subprocess.Output(succeeded: true, standardOutput: Fixture.catalogue)
                    case "create":
                        log.append("create \(arguments.dropFirst(2).first ?? "")")
                        return Subprocess.Output(succeeded: true, standardOutput: log.nextUdid(from: Fixture.udids))
                    case "boot":
                        let udid = arguments.dropFirst(2).first ?? ""
                        let present = ((try? overrides.labels(for: udid)) ?? []).sorted().joined(separator: ",")
                        log.append("boot \(udid)\(present.isEmpty ? "" : " with \(present)")")
                        return Subprocess.Output(succeeded: true, standardOutput: "")
                    case "spawn" where arguments.contains("print-disabled"):
                        log.append("read-back \(arguments.dropFirst(2).first ?? "")")
                        return readBack ?? Subprocess.Output(succeeded: true, standardOutput: listing)
                    default:
                        return Subprocess.Output(succeeded: true, standardOutput: "")
                    }
                },
                launch: { arguments in
                    if arguments.contains("build-for-testing") {
                        return TestRunEnvironment.Launched(exitCode: 0, answer: "✔ swift-sure run — xcodebuild build-for-testing")
                    }
                    if let flag = arguments.firstIndex(of: "-test-enumeration-output-path"), flag + 1 < arguments.count {
                        // Two tests, so the plan keeps both devices: a plan lowered to one shard deletes the second
                        // before it runs, and its boot goes off the record with it.
                        let document = #"{ "values": [{ "testPlan": "Default", "enabledTests": [{ "identifier": "GizmoTests/Gizmo/t1()" }, { "identifier": "GizmoTests/Gizmo/t2()" }] }] }"#
                        try Data(document.utf8).write(to: URL(fileURLWithPath: arguments[flag + 1]))
                    }
                    return TestRunEnvironment.Launched(exitCode: 0, answer: "")
                },
                buildSettings: { _ in
                    let json = #"[{ "buildSettings": { "BUILD_DIR": "\#(products.path)" } }]"#
                    return TestRunEnvironment.Launched(exitCode: 0, answer: "", output: Data(json.utf8))
                },
                armWatcher: { _, _, _ in
                    TestRunEnvironment.Watcher(identity: ShardLedger.Identity(pid: 4711, startMicroseconds: 111), watching: { true }, release: { true })
                },
                shardRunner: { _ in
                    TestRunEnvironment.Shards(
                        run: { assignments in
                            assignments.map { _ in
                                var outcomes = RunTestOutcomes()
                                if failing {
                                    outcomes.read("Test t1() failed after 0.001 seconds with 1 issue.")
                                }
                                return ShardOutcome(outcomes: outcomes, exitCode: failing ? 1 : 0, wallSeconds: 1, logPath: "/dev/null")
                            }
                        },
                        cancel: {}
                    )
                },
                listDirectory: { _ in [TestRunEnvironment.Entry(name: "Gizmo_Default.xctestrun", modified: Date(timeIntervalSince1970: 1_000_000))] },
                hostFacts: { TestRunEnvironment.HostFacts(performanceCores: 8, memoryGB: 32) },
                crashReports: { _ in [] },
                now: { Date(timeIntervalSince1970: 1_000_000) },
                projectSettings: { _ in
                    let index = log.count(of: "settings read")
                    log.append("settings read")
                    return reads.isEmpty ? settings : reads[min(index, reads.count - 1)]
                },
                serviceProfile: { _ in profile },
                overrides: overrides
            )
        }

        /// The settings of one application target carrying the keys given.
        static func settings(_ keys: [String: String]) -> TestRunEnvironment.Launched {
            let target = ["target": "Gizmo", "buildSettings": ["PRODUCT_TYPE": "com.apple.product-type.application"].merging(keys) { $1 }] as [String: Any]
            let data = (try? JSONSerialization.data(withJSONObject: [target])) ?? Data()
            return TestRunEnvironment.Launched(exitCode: 0, answer: "", output: data)
        }

        /// What `launchctl print-disabled system` prints for the labels given.
        static func listing(_ labels: [String]) -> String {
            "disabled services = {\n" + labels.map { "\t\"\($0)\" => disabled" }.joined(separator: "\n") + "\n}\n"
        }

        static var runtime: String {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
        }

        /// Four services: three the profile disables and one the runtime needs.
        static var profile: ServiceProfile {
            func entry(_ label: String, _ disposition: Disposition) -> ServiceEntry {
                ServiceEntry(label: label, domain: .daemon, start: .onDemand, ranAtBoot: true, peakFootprintMB: nil, cpuSeconds: nil, disposition: disposition)
            }
            return ServiceProfile(
                profileVersion: 1,
                runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A000"),
                deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                generated: "2026-10-01",
                method: ProfileMethod(costWindowSeconds: 60, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
                services: [entry("com.gizmo.a", .disable), entry("com.gizmo.b", .disable), entry("com.gizmo.c", .disable), entry("com.gizmo.core", .core)],
                capabilities: [:]
            )
        }

        static var catalogue: String {
            """
            {
              "devicetypes": [
                { "name": "iPhone 17", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17" }
              ],
              "runtimes": [
                {
                  "identifier": "\(runtime)", "version": "27.0", "isAvailable": true, "platform": "iOS",
                  "supportedDeviceTypes": [{ "name": "iPhone 17", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17" }]
                }
              ]
            }
            """
        }
    }
}
