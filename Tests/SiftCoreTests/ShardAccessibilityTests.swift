//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// Covers a shard device's accessibility preference being confirmed on after the boot and again before its tests start, rather than only written.
///
/// Every case drives a scripted runner, a recorded pause and a stepped clock, so nothing here spawns `simctl` or waits.
struct ShardAccessibilityTests {
    static var udid: String {
        "11111111-2222-3333-4444-555555555555"
    }

    /// A write the device switches back off a moment later is written again, and a run that then reads on goes ahead.
    @Test
    func bootWritesAgainWhenTheFirstWriteIsUndone() throws {
        let device = Device(readings: ["0", "1"])

        try ShardDevices.boot(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)

        #expect(device.writes == 4)
        #expect(device.pauses.count == 2)
    }

    /// A device that keeps switching the preference off refuses the run with the cause named.
    @Test
    func bootRefusesADeviceThatWillNotKeepAccessibilityOn() {
        let device = Device(readings: ["0"])
        var thrown: Error?

        do {
            try ShardDevices.boot(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)
        } catch {
            thrown = error
        }
        let text = thrown.map { "\($0)" } ?? ""

        #expect(thrown is ShardError)
        #expect(text.contains("did not keep accessibility on"))
        #expect(text.contains(Self.udid))
    }

    /// A preference that cannot be read is not known to be off, so the boot carries on.
    @Test
    func bootCarriesOnWhenThePreferenceCannotBeRead() throws {
        let device = Device(readings: [], readSucceeds: false)

        try ShardDevices.boot(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)

        #expect(device.writes == 2)
    }

    /// A write a freshly booted device refuses is tried again, and the boot goes ahead once a later write holds.
    @Test
    func bootWritesAgainWhenTheFirstWriteFails() throws {
        let device = Device(readings: ["1"])
        device.failingWrites = 1
        device.writeError = "Gizmo: device not ready\n"

        try ShardDevices.boot(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)

        #expect(device.writes == 3)
        #expect(device.pauses.count == 2)
    }

    /// Writes that never succeed on a device nobody saw off are carried on with, and the reason a caller reads names the write's own error.
    @Test
    func aWriteThatAlwaysFailsIsUnconfirmedAndNamesItsError() {
        let device = Device(readings: ["1"], writesSucceed: false)
        device.writeError = "Gizmo: device not ready\n"

        let restoration = SimulatorAccessibility.armConfirmed(udid: Self.udid, knownOff: false, run: device.run, pause: device.pause, now: device.now)

        guard case let .unconfirmed(reason) = restoration.state else {
            Issue.record("expected unconfirmed, got \(restoration.state)")
            return
        }

        #expect(reason.contains("Gizmo: device not ready"))
        #expect(reason.contains("rounds"))
        #expect(device.writes > 1)
    }

    /// A reading that is neither on nor off is a key nobody could read, so the boot carries on rather than calling it switched back off.
    @Test
    func bootCarriesOnWhenTheReadingIsNeitherOnNorOff() throws {
        let device = Device(readings: [""])

        try ShardDevices.boot(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)

        #expect(device.writes >= 2)
    }

    /// A preference read as something other than the off value before the tests is not known to be off, so a write that then fails is carried on with.
    @Test
    func theCheckBeforeTheTestsCarriesOnOverAnUnknownReadingAndAFailedWrite() throws {
        let device = Device(readings: [""], writesSucceed: false)

        try ShardDevices.confirmAccessibility(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)
    }

    /// A preference read off before the tests, whose write then fails, is known off and refuses the run.
    @Test
    func theCheckBeforeTheTestsRefusesAFailedWriteOverAnOffReading() {
        let device = Device(readings: ["0"], writesSucceed: false)

        #expect(throws: ShardError.self) {
            try ShardDevices.confirmAccessibility(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)
        }
    }

    /// A preference read off just before the tests is written again.
    @Test
    func theCheckBeforeTheTestsWritesOverAnOffReading() throws {
        let device = Device(readings: ["0", "1"])

        try ShardDevices.confirmAccessibility(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)

        #expect(device.writes == 2)
    }

    /// A preference read on just before the tests is left alone.
    @Test
    func theCheckBeforeTheTestsWritesNothingOverAnOnReading() throws {
        let device = Device(readings: ["1"])

        try ShardDevices.confirmAccessibility(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)

        #expect(device.writes == 0)
    }

    /// An overwrite that outlasts the write's budget before the tests refuses the run rather than reporting hosted tests as failures.
    @Test
    func theCheckBeforeTheTestsRefusesADeviceThatStaysOff() {
        let device = Device(readings: ["0"])

        #expect(throws: ShardError.self) {
            try ShardDevices.confirmAccessibility(udid: Self.udid, run: device.run, pause: device.pause, now: device.now)
        }
    }

    /// A stop that arrives after a failed write ends the arming there: nothing more is written and nothing is waited for.
    @Test
    func aStopAfterAFailedWriteEndsTheWritingAndTheWaiting() {
        let device = Device(readings: ["1"], writesSucceed: false)

        let restoration = SimulatorAccessibility.armConfirmed(
            udid: Self.udid,
            knownOff: false,
            run: device.run,
            pause: device.pause,
            now: device.now,
            stopped: { device.writes > 0 }
        )

        #expect(restoration.state == .unconfirmed(reason: "stopped"))
        #expect(device.writes == 1)
        #expect(device.pauses.isEmpty)
    }

    /// A stop that is already set before the arming begins writes nothing and waits for nothing.
    @Test
    func aStopBeforeTheFirstWriteWritesNothing() {
        let device = Device(readings: ["1"])

        let restoration = SimulatorAccessibility.armConfirmed(
            udid: Self.udid,
            knownOff: false,
            run: device.run,
            pause: device.pause,
            now: device.now,
            stopped: { true }
        )

        #expect(restoration.state == .unconfirmed(reason: "stopped"))
        #expect(device.writes == 0)
        #expect(device.pauses.isEmpty)
    }

    /// A stop that arrives after the writes succeeded ends the arming before the confirmation pause and the read-back.
    @Test
    func aStopAfterTheWritesSucceededTakesNoConfirmationPause() {
        let device = Device(readings: ["1"])

        let restoration = SimulatorAccessibility.armConfirmed(
            udid: Self.udid,
            knownOff: false,
            run: device.run,
            pause: device.pause,
            now: device.now,
            stopped: { device.writes >= SimulatorAccessibility.keys.count }
        )

        #expect(restoration.state == .unconfirmed(reason: "stopped"))
        #expect(device.writes == SimulatorAccessibility.keys.count)
        #expect(device.pauses.isEmpty)
        #expect(!device.commands.contains(SimulatorAccessibility.readArguments(udid: Self.udid)))
    }
}

extension ShardAccessibilityTests {
    /// A scripted device: the readings it answers in turn (the last one repeating), and every command it was given.
    final class Device {
        var readings: [String]
        var commands: [[String]] = []
        var pauses: [TimeInterval] = []
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let readSucceeds: Bool
        let writesSucceed: Bool
        /// How many writes fail before the rest follow `writesSucceed`.
        var failingWrites = 0
        var writeError = ""

        init(readings: [String], readSucceeds: Bool = true, writesSucceed: Bool = true) {
            self.readings = readings
            self.readSucceeds = readSucceeds
            self.writesSucceed = writesSucceed
        }

        var run: ShardDevices.Run {
            { _, arguments in
                self.commands.append(arguments)
                guard arguments == SimulatorAccessibility.readArguments(udid: ShardAccessibilityTests.udid) else {
                    guard arguments.contains("write") else {
                        return Subprocess.Output(succeeded: true, standardOutput: "")
                    }
                    if self.failingWrites > 0 {
                        self.failingWrites -= 1
                        return Subprocess.Output(succeeded: false, standardOutput: "", standardError: self.writeError)
                    }
                    return Subprocess.Output(succeeded: self.writesSucceed, standardOutput: "", standardError: self.writesSucceed ? "" : self.writeError)
                }
                guard self.readSucceeds else {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "defaults: some other failure\n")
                }
                let reading = self.readings.count > 1 ? self.readings.removeFirst() : self.readings[0]
                return Subprocess.Output(succeeded: true, standardOutput: "\(reading)\n")
            }
        }

        var pause: (TimeInterval) -> Void {
            {
                self.pauses.append($0)
                self.clock.addTimeInterval($0)
            }
        }

        var now: () -> Date {
            { self.clock }
        }

        var writes: Int {
            commands.filter { $0.contains("write") }.count
        }
    }
}
