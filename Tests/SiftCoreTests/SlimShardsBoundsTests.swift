//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Pins what a slim run's bounds and re-run line say: each bound belongs to the one operation it was chosen for, a deadline is recognised by the runner's own marker, and the re-run keeps `--stock`.
@Suite(.temporaryDirectories)
struct SlimShardsBoundsTests {
    // MARK: - The re-run line

    /// A run that asked for stock devices re-runs with stock devices.
    @Test
    func theRerunPrefixKeepsStock() throws {
        let root = try TemporaryDirectory.make("slim-bounds")
        func prefix(stock: Bool) -> String {
            TestRunRequest(
                scheme: "TestDemo",
                deviceTypeName: "iPhone 17",
                workingDirectory: root,
                repositoryRoot: root,
                executable: root.appendingPathComponent("swift-sure"),
                stock: stock
            ).rerunCommandPrefix
        }

        #expect(prefix(stock: true) == "swift-sure test --scheme TestDemo --device 'iPhone 17' --stock")
        #expect(prefix(stock: false) == "swift-sure test --scheme TestDemo --device 'iPhone 17'")
    }

    // MARK: - The spawn bounds

    /// Only the disabled-list read-back gets the read-back's bound; the accessibility spawns keep the default one.
    @Test
    func onlyTheReadBackSpawnGetsTheLongerBound() throws {
        let simctl = TestRunEnvironment.liveSimctl { _, _, deadline in
            Subprocess.Output(succeeded: true, standardOutput: "\(deadline)")
        }
        let udid = "00000000-0000-0000-0000-000000000000"
        let readBack = ["simctl", "spawn", udid, "launchctl", "print-disabled", "system"]
        let read = ["simctl", "spawn", udid, "defaults", "read", "com.apple.Accessibility", "Gizmo"]
        let write = ["simctl", "spawn", udid, "defaults", "write", "com.apple.Accessibility", "Gizmo", "-bool", "true"]

        let taken = try [readBack, read, write].map { try Double(simctl("/usr/bin/xcrun", $0).standardOutput) }

        #expect(taken == [ShardDevices.readBackDeadline, Subprocess.defaultDeadline, Subprocess.defaultDeadline])
        #expect(ShardDevices.readBackDeadline > Subprocess.defaultDeadline)
    }

    // MARK: - The settings read

    /// The settings read is wired to its own bound, not the longer default of the read that finds `BUILD_DIR`.
    @Test
    func theLiveSettingsReadIsBoundedAtItsOwnDeadline() throws {
        let root = try TemporaryDirectory.make("slim-bounds")
        let deadlines = Deadlines()
        let spawn: @Sendable (String, [String], TimeInterval, URL) throws -> Subprocess.Output = { _, _, deadline, _ in
            deadlines.append(deadline)
            return Subprocess.Output(succeeded: true, standardOutput: "[]")
        }

        _ = try TestRunEnvironment.liveProjectSettings(workingDirectory: root, spawn: spawn)(["-showBuildSettings"])
        _ = try TestRunEnvironment.liveBuildSettings(workingDirectory: root, spawn: spawn)(["-showBuildSettings"])

        #expect(deadlines.taken() == [60, 120])
        #expect(TestRunEnvironment.slimSettingsDeadline == 60)
    }

    /// A tool's own "timed out" is a failed read, and only the runner's marker is a deadline passed.
    @Test
    func aForeignTimedOutMessageIsAFailureNotTheBound() throws {
        let foreign = try decision(answer: "xcodebuild: error: The request timed out.\nsecond line")
        let deadline = try decision(answer: "the spawn timed out: env did not finish within 60 s and was ended")

        #expect(foreign == .stock(.unreadable("the build settings could not be read: xcodebuild: error: The request timed out.")))
        #expect(deadline == .stock(.unreadable("the build settings read passed its 60 s bound")))
    }

    /// The same holds for the read-back.
    @Test
    func aForeignTimedOutMessageOnTheReadBackIsAFailure() throws {
        let root = try TemporaryDirectory.make("slim-bounds")
        let record = SlimBootRecord()
        record.wrote(["com.gizmo.a"], forShard: 0)
        let provisioning = SlimProvisioning(
            environment: environment(root: root, settings: nil, readBack: Subprocess.Output(succeeded: false, standardOutput: "", standardError: "The request timed out.")),
            stockRequested: false,
            record: record
        )

        provisioning.readBack(shard: 0, udid: "11111111-2222-3333-4444-555555555555")

        #expect(record.shards == [0: .unverified("the read-back failed: The request timed out.")])
    }
}

private extension SlimShardsBoundsTests {
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

    /// How a run decides to boot when the settings read answers `answer` with a failure.
    func decision(answer: String) throws -> BootMode? {
        let root = try TemporaryDirectory.make("slim-bounds")
        let record = SlimBootRecord()
        let provisioning = SlimProvisioning(
            environment: environment(root: root, settings: TestRunEnvironment.Launched(exitCode: 1, answer: answer), readBack: nil),
            stockRequested: false,
            record: record
        )
        let invocation = try TestInvocation(scheme: "Gizmo", deviceType: "iPhone 17", osVersion: "27.0")
        let resolution = ShardDevices.Resolution(deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", runtime: Self.runtime, osVersion: "27.0")

        provisioning.decide(invocation, resolution: resolution)
        return record.mode
    }

    func environment(root: URL, settings: TestRunEnvironment.Launched?, readBack: Subprocess.Output?) -> TestRunEnvironment {
        let profile = Self.profile
        return TestRunEnvironment(
            simctl: { _, _ in readBack ?? Subprocess.Output(succeeded: true, standardOutput: "") },
            launch: { _ in TestRunEnvironment.Launched(exitCode: 0, answer: "") },
            buildSettings: { _ in TestRunEnvironment.Launched(exitCode: 0, answer: "") },
            armWatcher: { _, _, _ in
                TestRunEnvironment.Watcher(identity: ShardLedger.Identity(pid: 1, startMicroseconds: 1), watching: { true }, release: { true })
            },
            shardRunner: { _ in TestRunEnvironment.Shards(run: { _ in [] }, cancel: {}) },
            listDirectory: { _ in [] },
            hostFacts: { TestRunEnvironment.HostFacts(performanceCores: 8, memoryGB: 32) },
            crashReports: { _ in [] },
            projectSettings: { _ in settings ?? TestRunEnvironment.Launched(exitCode: 1, answer: "unused") },
            serviceProfile: { _ in profile },
            overrides: DisabledServicesOverride(root: root.appendingPathComponent("var-tmp"))
        )
    }

    static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    }

    static var profile: ServiceProfile {
        ServiceProfile(
            profileVersion: 1,
            runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A000"),
            deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            generated: "2026-10-01",
            method: ProfileMethod(costWindowSeconds: 60, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
            services: [ServiceEntry(label: "com.gizmo.a", domain: .daemon, start: .onDemand, ranAtBoot: true, peakFootprintMB: nil, cpuSeconds: nil, disposition: .disable)],
            capabilities: [:]
        )
    }
}
