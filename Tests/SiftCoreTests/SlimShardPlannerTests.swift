//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Covers the shard count and the overhead a plan charges for each way a run can boot: slim devices are given their own default and overhead, and the count is settled once the boot decision is known.
@Suite(.temporaryDirectories)
struct SlimShardPlannerTests {
    // MARK: - The planner's own figures

    /// The slim default is the smallest of half the performance cores, a quarter of the memory and six; the stock default stays at three.
    @Test
    func theSlimDefaultIsCappedAtSixAndTheStockDefaultAtThree() {
        #expect(ShardPlanner.defaultShardCount(performanceCores: 12, memoryGB: 48, slim: true) == 6)
        #expect(ShardPlanner.defaultShardCount(performanceCores: 8, memoryGB: 16, slim: true) == 4)
        #expect(ShardPlanner.defaultShardCount(performanceCores: 12, memoryGB: 48) == 3)
        #expect(ShardPlanner.defaultShardCount(performanceCores: 12, memoryGB: 48, slim: false) == 3)
    }

    /// A plan given the slim overhead charges every shard 50 s on top of its tests.
    @Test
    func aSlimPlanChargesFiftySecondsPerShard() {
        let tests = (1 ... 2).compactMap { TestIdentifier(enumerated: "GizmoTests/Gizmo/t\($0)()") }
        let plan = ShardPlanner.plan(tests: tests, shards: 2, overheadSeconds: ShardPlanner.slimOverheadSeconds, duration: { _ in 100 })

        #expect(plan.overheadSeconds == 50)
        #expect(plan.shards.map(\.predictedSeconds) == [150, 150])
    }

    // MARK: - The count a run settles on

    /// No `--shards`, slim devices, twelve performance cores and 48 GB: six devices, and the plan is charged the slim overhead.
    @Test
    func aSlimRunWithoutShardsCreatesSixAndChargesTheSlimOverhead() throws {
        let run = try Fixture().run(requested: nil, performanceCores: 12, memoryGB: 48)

        #expect(run.created == 6)
        #expect(run.answer.contains("(predicted 51s)"))
    }

    /// No `--shards`, and an unreadable declaration decides stock: three devices, charged the stock overhead, however many the slim default would have made.
    @Test
    func aRunThatFallsBackToStockCreatesThreeAndChargesTheStockOverhead() throws {
        var fixture = try Fixture()
        fixture.readable = false

        let run = fixture.run(requested: nil, performanceCores: 12, memoryGB: 48)

        #expect(run.created == 3)
        #expect(run.answer.contains("(predicted 22s)"))
    }

    /// `--stock` is stock from the start: three devices and the stock overhead.
    @Test
    func aStockRunWithoutShardsCreatesThree() throws {
        var fixture = try Fixture()
        fixture.stock = true

        let run = fixture.run(requested: nil, performanceCores: 12, memoryGB: 48)

        #expect(run.created == 3)
        #expect(run.answer.contains("(predicted 22s)"))
    }

    /// An explicit `--shards 5` is used as given when the decision comes out stock.
    @Test
    func anExplicitCountIsUsedAsGivenWhenTheDecisionIsStock() throws {
        var fixture = try Fixture()
        fixture.readable = false

        let run = fixture.run(requested: 5, performanceCores: 12, memoryGB: 48)

        #expect(run.created == 5)
    }
}

private extension SlimShardPlannerTests {
    /// What one run left behind: the devices it created and its answer.
    struct Ran {
        let created: Int
        let answer: String
    }

    /// Counts creates and hands out a distinct udid for each.
    final class Log: @unchecked Sendable {
        private let gate = NSLock()
        private var count = 0

        var created: Int {
            gate.withLock { count }
        }

        func nextUdid() -> String {
            gate.withLock {
                count += 1
                return String(format: "00000000-0000-0000-0000-%012d", count)
            }
        }
    }

    /// A sharded run of six one-second tests on fakes, booting slim unless a dial says otherwise.
    struct Fixture {
        let root: URL
        var stock = false
        var readable = true

        init() throws {
            root = try TemporaryDirectory.make("slim-planner")
        }

        func run(requested: Int?, performanceCores: Int, memoryGB: Int) -> Ran {
            let log = Log()
            let request = TestRunRequest(
                scheme: "Gizmo",
                deviceTypeName: "iPhone 17",
                requestedShards: requested,
                workingDirectory: root,
                repositoryRoot: root,
                executable: root.appendingPathComponent("swift-sure"),
                stock: stock
            )
            let result = TestRun(request: request, environment: environment(log, performanceCores: performanceCores, memoryGB: memoryGB)).run()
            return Ran(created: log.created, answer: result.answer)
        }

        func environment(_ log: Log, performanceCores: Int, memoryGB: Int) -> TestRunEnvironment {
            let products = root.appendingPathComponent("Build/Products")
            let readable = readable
            return TestRunEnvironment(
                simctl: simctl(log),
                launch: { arguments in
                    if let flag = arguments.firstIndex(of: "-test-enumeration-output-path"), flag + 1 < arguments.count {
                        let enabled = (1 ... 6).map { #"{ "identifier": "GizmoTests/Gizmo/t\#($0)()" }"# }.joined(separator: ", ")
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
                            assignments.map { _ in ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 0, wallSeconds: 1, logPath: "/dev/null") }
                        },
                        cancel: {}
                    )
                },
                listDirectory: { _ in [TestRunEnvironment.Entry(name: "Gizmo_Default.xctestrun", modified: Date(timeIntervalSince1970: 1_000_000))] },
                hostFacts: { TestRunEnvironment.HostFacts(performanceCores: performanceCores, memoryGB: memoryGB) },
                crashReports: { _ in [] },
                now: { Date(timeIntervalSince1970: 1_000_000) },
                projectSettings: { _ in
                    guard readable else {
                        return TestRunEnvironment.Launched(exitCode: 1, answer: "no settings")
                    }
                    let target = ["target": "Gizmo", "buildSettings": ["PRODUCT_TYPE": "com.apple.product-type.application"]] as [String: Any]
                    return TestRunEnvironment.Launched(exitCode: 0, answer: "", output: (try? JSONSerialization.data(withJSONObject: [target])) ?? Data())
                },
                serviceProfile: { _ in Self.profile },
                overrides: DisabledServicesOverride(root: root.appendingPathComponent("var-tmp"))
            )
        }

        func simctl(_ log: Log) -> @Sendable (String, [String]) throws -> Subprocess.Output {
            { _, arguments in
                switch arguments.dropFirst().first {
                case "list" where arguments.contains("devicetypes"):
                    Subprocess.Output(succeeded: true, standardOutput: Self.catalogue)
                case "list":
                    Subprocess.Output(succeeded: true, standardOutput: #"{ "devices": { "\#(Self.runtime)": [] } }"#)
                case "create":
                    Subprocess.Output(succeeded: true, standardOutput: log.nextUdid())
                case "spawn" where arguments.contains("print-disabled"):
                    Subprocess.Output(succeeded: true, standardOutput: "disabled services = {\n}\n")
                default:
                    Subprocess.Output(succeeded: true, standardOutput: "")
                }
            }
        }

        static var runtime: String {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
        }

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
                services: [entry("com.gizmo.a", .disable), entry("com.gizmo.core", .core)],
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
