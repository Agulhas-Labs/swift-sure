//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorServices

/// A run's seams answered from memory for a build that writes one `.xctestrun` per plan, each enumerating its own tests — the shape a scheme with several test plans gives a build that names none.
///
/// Every `xcodebuild` it is asked for is kept, so a test reads which `.xctestrun` each call named.
struct PlanRunFake {
    let root: URL
    /// Each plan's enumerated tests, by plan name.
    var tests: [String: [String]]
    /// The schemes the run reads where it must choose among the files.
    var schemes: SchemeSurvey = .unread
    /// The plans whose shard calls exit 1.
    var failing: Set<String> = []
    /// The plans whose shard calls report no test ended at all, so every test they were given is missing.
    var silent: Set<String> = []
    /// When set, each shard call reports every test it was given as ended, in this many seconds by the test's own name (one second where unnamed), failed where its plan is in ``failing``.
    var endings: [String: Double]?
    /// When set, the first shard call to start holds until a device is deleted (every other call runs straight through), so a test sees a device go while another still runs whatever the machine's load; a run that never deletes one releases it after ``holdBound``.
    var holdsFirstCallForDelete = false
    /// The longest the held call waits: reached only where no device is deleted while it runs, which the test then reports.
    static var holdBound: TimeInterval {
        60
    }

    /// Every `simctl` call the run made, in order.
    let simctlCalls = Launches()
    /// The shard calls a device was deleted during, by argv.
    let deletedDuring = Launches()

    static var moment: Date {
        Date(timeIntervalSince1970: 1_000_000)
    }

    static func xctestrunName(plan: String) -> String {
        "TestDemo_\(plan)_iphonesimulator27.0-arm64.xctestrun"
    }

    /// A survey holding one shared scheme named `TestDemo` that lists `plans`, the first marked default.
    static func scheme(plans: [String]) -> SchemeSurvey {
        let references = plans.enumerated().map { offset, plan in
            SchemeFile.PlanReference(reference: "container:TestPlans/\(plan).xctestplan", isDefault: offset == 0)
        }
        let file = SchemeFile(
            name: "TestDemo",
            path: "TestDemo.xcodeproj/xcshareddata/xcschemes/TestDemo.xcscheme",
            container: "TestDemo.xcodeproj",
            containerScope: "",
            isShared: true,
            testAction: SchemeFile.TestAction(testables: [], planReferences: references)
        )
        return SchemeSurvey(schemes: [file], unreadable: [])
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

    /// The `-xctestrun` file an argument vector names, by name.
    static func xctestrun(in argv: [String]) -> String? {
        guard let flag = argv.firstIndex(of: "-xctestrun"), flag + 1 < argv.count else {
            return nil
        }
        return URL(fileURLWithPath: argv[flag + 1]).lastPathComponent
    }

    func environment(_ launches: Launches) -> TestRunEnvironment {
        let products = root.appendingPathComponent("Build/Products")
        let names = tests.keys.sorted().map(Self.xctestrunName(plan:))
        let tests = tests
        let schemes = schemes
        return TestRunEnvironment(
            simctl: Self.simctl(recording: simctlCalls),
            launch: { arguments in
                launches.append(arguments)
                guard !arguments.contains("build-for-testing") else {
                    return TestRunEnvironment.Launched(exitCode: 0, answer: "✔ swift-sure run — xcodebuild build-for-testing")
                }
                if let flag = arguments.firstIndex(of: "-test-enumeration-output-path"), let file = Self.xctestrun(in: arguments) {
                    let plan = tests.keys.first { file == Self.xctestrunName(plan: $0) } ?? ""
                    let identifiers = (tests[plan] ?? []).map { #"{ "identifier": "\#($0)" }"# }.joined(separator: ", ")
                    let document = #"{ "values": [{ "testPlan": "\#(plan)", "enabledTests": [\#(identifiers)] }] }"#
                    try Data(document.utf8).write(to: URL(fileURLWithPath: arguments[flag + 1]))
                }
                return TestRunEnvironment.Launched(exitCode: 0, answer: "")
            },
            buildSettings: { _ in
                TestRunEnvironment.Launched(exitCode: 0, answer: "", output: Data(#"[{ "buildSettings": { "BUILD_DIR": "\#(products.path)" } }]"#.utf8))
            },
            armWatcher: { _, _, _ in
                TestRunEnvironment.Watcher(identity: ShardLedger.Identity(pid: 4711, startMicroseconds: 111), watching: { true }, release: { true })
            },
            shardRunner: { [failing, silent, endings, holdsFirstCallForDelete, simctlCalls, deletedDuring] _ in
                let firstCall = FirstCall()
                return TestRunEnvironment.Shards(
                    run: { assignments in
                        assignments.map { assignment in
                            launches.append(assignment.argv)
                            let deletesBefore = Self.deletes(in: simctlCalls)
                            if holdsFirstCallForDelete, firstCall.claim() {
                                let deadline = Date().addingTimeInterval(Self.holdBound)
                                while Date() < deadline, Self.deletes(in: simctlCalls) == deletesBefore {
                                    Thread.sleep(forTimeInterval: 0.01)
                                }
                            }
                            if Self.deletes(in: simctlCalls) > deletesBefore {
                                deletedDuring.append(assignment.argv)
                            }
                            let file = Self.xctestrun(in: assignment.argv) ?? ""
                            let failed = failing.contains { file == Self.xctestrunName(plan: $0) }
                            var outcomes = RunTestOutcomes()
                            let mute = silent.contains { file == Self.xctestrunName(plan: $0) }
                            for argument in assignment.argv where endings != nil && !mute && argument.hasPrefix("-only-testing:") {
                                let name = String(argument.split(separator: "/").last ?? "")
                                let seconds = endings?[name] ?? 1
                                outcomes.read("◇ Test \(name) started.")
                                outcomes.read(failed ? "✘ Test \(name) failed after \(seconds) seconds with 1 issue." : "✔ Test \(name) passed after \(seconds) seconds.")
                            }
                            return ShardOutcome(outcomes: outcomes, exitCode: failed ? 1 : 0, wallSeconds: 1, logPath: "/dev/null")
                        }
                    },
                    cancel: {}
                )
            },
            listDirectory: { _ in names.map { TestRunEnvironment.Entry(name: $0, modified: Self.moment) } },
            hostFacts: { TestRunEnvironment.HostFacts(performanceCores: 8, memoryGB: 32) },
            crashReports: { _ in [] },
            now: { Self.moment },
            pause: { _ in },
            derivedDataRoot: { URL(fileURLWithPath: "/nonexistent/DerivedData") },
            schemes: { schemes }
        )
    }

    /// How many `simctl delete` calls `calls` holds.
    static func deletes(in calls: Launches) -> Int {
        calls.taken().count { $0.dropFirst().first == "delete" }
    }

    private static func simctl(recording calls: Launches) -> @Sendable (String, [String]) throws -> Subprocess.Output {
        let counter = Launches()
        return { _, arguments in
            calls.append(arguments)
            switch arguments.dropFirst().first {
            case "list" where arguments.contains("devicetypes"):
                return Subprocess.Output(succeeded: true, standardOutput: catalogue)
            case "list":
                return Subprocess.Output(succeeded: true, standardOutput: #"{ "devices": {} }"#)
            case "create":
                counter.append([])
                return Subprocess.Output(succeeded: true, standardOutput: String(format: "00000000-0000-0000-0000-%012d", counter.taken().count))
            case "spawn" where arguments.contains("read"):
                return Subprocess.Output(succeeded: true, standardOutput: "1\n")
            default:
                return Subprocess.Output(succeeded: true, standardOutput: "")
            }
        }
    }

    private static var catalogue: String {
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

extension PlanRunFake {
    /// Every `xcodebuild` the run asked for, in order, from whichever thread asked.
    final class Launches: @unchecked Sendable {
        private let gate = NSLock()
        private var argvs: [[String]] = []

        func append(_ argv: [String]) {
            gate.withLock { argvs.append(argv) }
        }

        func taken() -> [[String]] {
            gate.withLock { argvs }
        }
    }
}

/// Whether a shard call is the first of its run, claimed once under a lock by whichever call gets there first.
private final class FirstCall: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
