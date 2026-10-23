//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Pins how the two reads of the build settings share one budget, what the reason names when both fail, and which line of a failed read's output is its reason.
@Suite(.temporaryDirectories)
struct SlimReadBudgetTests {
    /// A first read that fails late leaves too little for a second, so there is none and the first failure decides.
    @Test
    func aLateFailureIsNotRetried() throws {
        let fixture = try Fixture(reads: [(takes: 59, answer: Self.failure("late"))])

        let reason = try fixture.decide()

        #expect(fixture.bounds() == [60])
        #expect(reason == .stock(.unreadable("the build settings could not be read: xcodebuild: error: late")))
    }

    /// A first read that fails early leaves the retry what is left of the minute, not a minute of its own.
    @Test
    func theRetryIsHeldToWhatIsLeft() throws {
        let fixture = try Fixture(reads: [
            (takes: 20, answer: Self.failure("early")),
            (takes: 1, answer: Self.timeout),
        ])

        _ = try fixture.decide()

        #expect(fixture.bounds() == [60, 40])
    }

    /// A retry that is just worth starting still runs, with the time left.
    @Test
    func aRetryWithFiveSecondsLeftRuns() throws {
        let fixture = try Fixture(reads: [
            (takes: 55, answer: Self.failure("edge")),
            (takes: 1, answer: Self.timeout),
        ])

        _ = try fixture.decide()

        #expect(fixture.bounds() == [60, 5])
    }

    /// Both reads failing, the second by timeout, the reason names the bound and the first failure.
    @Test
    func aTimedOutRetryNamesTheFirstFailure() throws {
        let fixture = try Fixture(reads: [
            (takes: 10, answer: Self.failure("first")),
            (takes: 50, answer: Self.timeout),
        ])

        let reason = try fixture.decide()

        #expect(reason == .stock(.unreadable("the build settings read passed its 50 s bound (the first read failed: xcodebuild: error: first)")))
    }

    /// Both reads failing outright, the reason names both.
    @Test
    func twoFailuresNameBoth() throws {
        let fixture = try Fixture(reads: [
            (takes: 1, answer: Self.failure("first")),
            (takes: 1, answer: Self.failure("second")),
        ])

        let reason = try fixture.decide()

        #expect(reason == .stock(.unreadable("the build settings could not be read: xcodebuild: error: second (the first read failed: xcodebuild: error: first)")))
    }

    /// Both reads failing for the same reason, the reason is named once, without the suffix that would repeat it.
    @Test
    func twoIdenticalFailuresNameTheReasonOnce() throws {
        let fixture = try Fixture(reads: [
            (takes: 1, answer: Self.failure("same")),
            (takes: 1, answer: Self.failure("same")),
        ])

        let reason = try fixture.decide()

        #expect(reason == .stock(.unreadable("the build settings could not be read: xcodebuild: error: same")))
    }

    /// The live environment hands the bound a read is given to the spawn, not the fixed bound of the single-argument read.
    @Test
    func theLiveEnvironmentHandsTheGivenBoundToTheSpawn() throws {
        let root = try TemporaryDirectory.make("slim-budget")
        let deadlines = Deadlines()
        let spawn: @Sendable (String, [String], TimeInterval, URL) throws -> Subprocess.Output = { _, _, deadline, _ in
            deadlines.append(deadline)
            return Subprocess.Output(succeeded: true, standardOutput: "[]")
        }
        let request = TestRunRequest(scheme: "Gizmo", deviceTypeName: "iPhone 17", workingDirectory: root, repositoryRoot: root, executable: root.appendingPathComponent("swift-sure"))
        let environment = TestRunEnvironment.live(for: request, children: SetAsideChildren(), settingsSpawn: spawn)

        _ = try environment.projectSettingsWithin(["-showBuildSettings"], 37)

        #expect(deadlines.taken() == [37])
    }

    /// A warning that mentions `error:` does not outrank a later line that begins with it.
    @Test
    func aLaterErrorLineBeatsAnEarlierWarning() {
        #expect(SlimProvisioning.errorLine(of: "warning: no error: here\nError: real failure") == "Error: real failure")
        #expect(SlimProvisioning.errorLine(of: "  error: one\nnote\n  ERROR: two") == "ERROR: two")
        #expect(SlimProvisioning.errorLine(of: "warning: no Error: here\nplain") == "warning: no Error: here")
        #expect(SlimProvisioning.errorLine(of: "") == "it printed nothing")
    }
}

private extension SlimReadBudgetTests {
    static var timeout: String {
        "the spawn timed out: env did not finish within 60 s and was ended"
    }

    static func failure(_ word: String) -> String {
        "xcodebuild: error: \(word)"
    }

    /// The deadlines a spawn seam was handed, in order.
    final class Deadlines: @unchecked Sendable {
        private let gate = NSLock()
        private var values: [TimeInterval] = []

        func append(_ value: TimeInterval) {
            gate.withLock { values.append(value) }
        }

        func taken() -> [TimeInterval] {
            gate.withLock { values }
        }
    }

    /// A clock the scripted reads advance, and the bounds they were handed.
    final class Fixture: @unchecked Sendable {
        private let gate = NSLock()
        private var now: TimeInterval = 1000
        private var taken: [TimeInterval] = []
        private var remaining: [(takes: TimeInterval, answer: String)]
        private let root: URL

        init(reads: [(takes: TimeInterval, answer: String)]) throws {
            remaining = reads
            root = try TemporaryDirectory.make("slim-budget")
        }

        func bounds() -> [TimeInterval] {
            gate.withLock { taken }
        }

        func decide() throws -> BootMode? {
            let record = SlimBootRecord()
            let provisioning = SlimProvisioning(
                environment: environment(),
                stockRequested: false,
                record: record,
                clock: { self.gate.withLock { self.now } }
            )
            let invocation = try TestInvocation(scheme: "Gizmo", deviceType: "iPhone 17", osVersion: "27.0")
            let resolution = ShardDevices.Resolution(deviceType: SlimReadBudgetTests.deviceType, runtime: SlimReadBudgetTests.runtime, osVersion: "27.0")
            provisioning.decide(invocation, resolution: resolution)
            return record.mode
        }

        private func read(within bound: TimeInterval) -> TestRunEnvironment.Launched {
            gate.withLock {
                taken.append(bound)
                let next = remaining.isEmpty ? (takes: 0, answer: "") : remaining.removeFirst()
                now += next.takes
                return TestRunEnvironment.Launched(exitCode: 1, answer: next.answer)
            }
        }

        private func environment() -> TestRunEnvironment {
            let profile = SlimReadBudgetTests.profile
            return TestRunEnvironment(
                simctl: { _, _ in Subprocess.Output(succeeded: true, standardOutput: "") },
                launch: { _ in TestRunEnvironment.Launched(exitCode: 0, answer: "") },
                buildSettings: { _ in TestRunEnvironment.Launched(exitCode: 0, answer: "") },
                armWatcher: { _, _, _ in
                    TestRunEnvironment.Watcher(identity: ShardLedger.Identity(pid: 1, startMicroseconds: 1), watching: { true }, release: { true })
                },
                shardRunner: { _ in TestRunEnvironment.Shards(run: { _ in [] }, cancel: {}) },
                listDirectory: { _ in [] },
                hostFacts: { TestRunEnvironment.HostFacts(performanceCores: 8, memoryGB: 32) },
                crashReports: { _ in [] },
                projectSettings: { _ in TestRunEnvironment.Launched(exitCode: 1, answer: "unused") },
                projectSettingsWithin: { _, bound in self.read(within: bound) },
                serviceProfile: { _ in profile },
                overrides: DisabledServicesOverride(root: root.appendingPathComponent("var-tmp"))
            )
        }
    }

    static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    }

    static var deviceType: String {
        "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
    }

    static var profile: ServiceProfile {
        ServiceProfile(
            profileVersion: 1,
            runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A000"),
            deviceType: deviceType,
            generated: "2026-10-01",
            method: ProfileMethod(costWindowSeconds: 60, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
            services: [ServiceEntry(label: "com.gizmo.a", domain: .daemon, start: .onDemand, ranAtBoot: true, peakFootprintMB: nil, cpuSeconds: nil, disposition: .disable)],
            capabilities: [:]
        )
    }
}
