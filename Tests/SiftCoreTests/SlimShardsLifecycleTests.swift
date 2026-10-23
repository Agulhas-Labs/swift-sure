//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Covers what a slim run leaves under its overrides root and on its record: no override written once a teardown has begun, every device's directory removed under the root the run wrote to, and no boot kept for a device a lowered plan deleted — every `simctl` and `xcodebuild` answered from memory, the root a temporary directory.
@Suite(.temporaryDirectories)
struct SlimShardsLifecycleTests {
    // MARK: - A cancellation before the writes

    /// A write that arrives after a cancellation's teardown writes nothing: the teardown has already deleted the devices and their record, so a directory written now is one nothing would remove.
    @Test
    func noOverrideIsWrittenOnceTheRunIsCancelled() throws {
        let fixture = try Fixture()
        let environment = fixture.environment(Log())
        let state = TestRun.State()
        try state.began(with: ShardLedger(repositoryRoot: fixture.root, prefix: "abcdef", owner: ShardLedger.Identity.current()))
        for index in 0 ..< 2 {
            try state.create(shard: index, resolution: Fixture.resolution, simctl: environment.simctl)
        }
        let udids = state.udids()
        let slim = SlimProvisioning(environment: environment, stockRequested: false, record: SlimBootRecord())
        try slim.decide(TestInvocation(scheme: "Gizmo", deviceType: "iPhone 17", osVersion: "27.0"), resolution: Fixture.resolution)

        _ = state.cancelling(exitCode: 130)
        _ = state.teardown(children: SetAsideChildren(), simctl: environment.simctl, overrides: environment.overrides, releasingWatcher: true)
        slim.writeOverrides(to: udids, unlessEnded: state.unlessEnded)

        #expect(udids == Array(Fixture.udids.prefix(2)))
        #expect(try fixture.overridden(udids).isEmpty)
    }

    // MARK: - The root teardown removes under

    /// Every created device's directory goes with it under the root the run wrote to, and so does the directory of a device the opening sweep deleted for a run that is no longer running.
    @Test
    func everyDeviceDirectoryIsRemovedUnderTheRunsOwnRoot() throws {
        var fixture = try Fixture()
        fixture.failing = true
        let swept = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        fixture.listed = try [ShardDevices.Device(udid: swept, name: ShardDeviceName(prefix: ShardLedger.devicePrefix(in: fixture.root), runID: "0f9e8d7c", index: 0).text)]
        try fixture.overrides.write(["com.gizmo.a"], for: swept)

        let run = fixture.run()

        #expect(run.log.count(of: "boot ") == 2)
        #expect(run.log.count(of: "delete \(swept)") == 1)
        #expect(try fixture.overridden(Fixture.udids + [swept]).isEmpty)
        #expect(run.answer.contains("2 simulators created, 2 deleted · slim: 3 of 4 services off"))
        #expect(!run.answer.contains("tmp directory left"))
    }

    /// The watcher deletes under the root it is given, as the run's own teardown does.
    @Test
    func theWatcherRemovesUnderTheRootItIsGiven() throws {
        let fixture = try Fixture()
        let udid = Fixture.udids[0]
        var ledger = try ShardLedger(repositoryRoot: fixture.root, runID: "0f9e8d7c", prefix: "a1b2c3", owner: ShardLedger.Identity(pid: 4711, startMicroseconds: 111), started: { _ in nil })
        try ledger.recordIntent(shard: 0)
        try ledger.record(udid: udid, forShard: 0)
        try fixture.overrides.write(["com.gizmo.a"], for: udid)

        let status = ShardGuardian.sweep(
            read: nil,
            runID: "0f9e8d7c",
            repositoryRoot: fixture.root,
            overrides: fixture.overrides,
            run: { _, _ in Subprocess.Output(succeeded: true, standardOutput: "") },
            endSessions: { _ in }
        )

        #expect(status == 0)
        #expect(try fixture.overridden([udid]).isEmpty)
    }

    // MARK: - A lowered plan

    /// Four devices lowered to three shards keep no boot for the fourth: the devices line speaks only of shards that ran, and its directory went with its delete.
    @Test
    func aLoweredPlanKeepsNoBootForTheDeletedDevice() throws {
        var fixture = try Fixture()
        fixture.failing = true
        fixture.shards = 4
        fixture.tests = ["t1()", "t2()", "t3()"]
        fixture.unapplied = [Fixture.udids[3]]

        let run = fixture.run()

        #expect(run.log.count(of: "read-back") == 4)
        #expect(run.record.shards.keys.sorted() == [0, 1, 2])
        #expect(!run.answer.contains("shard 4"))
        #expect(!run.answer.contains("not slim"))
        #expect(run.answer.contains("4 simulators created, 4 deleted · slim: 3 of 4 services off"))
        #expect(try fixture.overridden(Fixture.udids).isEmpty)
    }
}

private extension SlimShardsLifecycleTests {
    /// What one run left behind: its event log, the record of how it booted, and its answer.
    struct Ran {
        let log: Log
        let record: SlimBootRecord
        let answer: String
    }

    /// An event log the boot threads append to side by side, which also hands out the next udid a create prints.
    final class Log: @unchecked Sendable {
        private let gate = NSLock()
        private var events: [String] = []
        private var created = 0

        func append(_ event: String) {
            gate.withLock { events.append(event) }
        }

        func count(of prefix: String) -> Int {
            gate.withLock { events.filter { $0.hasPrefix(prefix) }.count }
        }

        func nextUdid() -> String {
            gate.withLock {
                defer { created += 1 }
                return Fixture.udids[created]
            }
        }
    }

    /// A slim sharded run on fakes, its overrides under a temporary root, with the dials a test turns.
    struct Fixture {
        static let udids = [
            "11111111-2222-3333-4444-555555555555",
            "66666666-7777-8888-9999-000000000000",
            "22222222-3333-4444-5555-666666666666",
            "77777777-8888-9999-0000-111111111111",
        ]

        let root: URL
        let overrides: DisabledServicesOverride
        var shards = 2
        var tests = ["t1()"]
        var failing = false
        var listed: [ShardDevices.Device] = []
        var unapplied: Set<String> = []

        init() throws {
            root = try TemporaryDirectory.make("slim-lifecycle")
            overrides = DisabledServicesOverride(root: root.appendingPathComponent("var-tmp"))
        }

        /// The udids among `udids` whose override directory exists under the temporary root.
        func overridden(_ udids: [String]) throws -> [String] {
            try udids.filter { try FileManager.default.fileExists(atPath: overrides.directory(for: $0).path) }
        }

        func run() -> Ran {
            let log = Log()
            let request = TestRunRequest(
                scheme: "Gizmo",
                deviceTypeName: "iPhone 17",
                requestedShards: shards,
                workingDirectory: root,
                repositoryRoot: root,
                executable: root.appendingPathComponent("swift-sure")
            )
            let run = TestRun(request: request, environment: environment(log))
            let result = run.run()
            return Ran(log: log, record: run.slimBoots, answer: result.answer)
        }

        func environment(_ log: Log) -> TestRunEnvironment {
            let products = root.appendingPathComponent("Build/Products")
            let tests = tests
            let failing = failing
            return TestRunEnvironment(
                simctl: simctl(log),
                launch: { arguments in
                    if arguments.contains("build-for-testing") {
                        return TestRunEnvironment.Launched(exitCode: 0, answer: "✔ swift-sure run — xcodebuild build-for-testing")
                    }
                    if let flag = arguments.firstIndex(of: "-test-enumeration-output-path"), flag + 1 < arguments.count {
                        let enabled = tests.map { #"{ "identifier": "GizmoTests/Gizmo/\#($0)" }"# }.joined(separator: ", ")
                        let document = #"{ "values": [{ "testPlan": "Default", "enabledTests": [\#(enabled)] }] }"#
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
                    let target = ["target": "Gizmo", "buildSettings": ["PRODUCT_TYPE": "com.apple.product-type.application"]] as [String: Any]
                    return TestRunEnvironment.Launched(exitCode: 0, answer: "", output: (try? JSONSerialization.data(withJSONObject: [target])) ?? Data())
                },
                serviceProfile: { _ in Fixture.profile },
                overrides: overrides
            )
        }

        func simctl(_ log: Log) -> @Sendable (String, [String]) throws -> Subprocess.Output {
            let overrides = overrides
            let listed = listed
            let unapplied = unapplied
            return { _, arguments in
                let udid = arguments.dropFirst(2).first ?? ""
                switch arguments.dropFirst().first {
                case "list" where arguments.contains("devicetypes"):
                    return Subprocess.Output(succeeded: true, standardOutput: Fixture.catalogue)
                case "list":
                    let devices = listed.map { #"{ "udid": "\#($0.udid)", "name": "\#($0.name)", "state": "Shutdown", "isAvailable": true }"# }
                    return Subprocess.Output(succeeded: true, standardOutput: #"{ "devices": { "\#(Fixture.runtime)": [\#(devices.joined(separator: ", "))] } }"#)
                case "create":
                    let created = log.nextUdid()
                    log.append("create \(created)")
                    return Subprocess.Output(succeeded: true, standardOutput: created)
                case "boot":
                    log.append("boot \(udid)")
                    return Subprocess.Output(succeeded: true, standardOutput: "")
                case "spawn" where arguments.contains("print-disabled"):
                    log.append("read-back \(udid)")
                    let labels = unapplied.contains(udid) ? [] : ((try? overrides.labels(for: udid)) ?? []).sorted()
                    let listing = "disabled services = {\n" + labels.map { "\t\"\($0)\" => disabled" }.joined(separator: "\n") + "\n}\n"
                    return Subprocess.Output(succeeded: true, standardOutput: listing)
                case "delete":
                    log.append("delete \(udid)")
                    return Subprocess.Output(succeeded: true, standardOutput: "")
                default:
                    return Subprocess.Output(succeeded: true, standardOutput: "")
                }
            }
        }

        static var resolution: ShardDevices.Resolution {
            ShardDevices.Resolution(deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", runtime: runtime, osVersion: "27.0")
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
