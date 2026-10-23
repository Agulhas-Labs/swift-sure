//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// Covers the accessibility preference being confirmed through a whole run: at each device's boot and again before its tests start.
///
/// Every case drives `TestRun` through its fake environment, with a clock that ticks on each read and a pause that returns at once, so nothing here waits.
@Suite(.temporaryDirectories)
struct TestRunAccessibilityTests {
    /// A device that boots with the preference on and then reads off for good is refused before its tests, and every device the run provisioned is deleted.
    @Test
    func aDeviceThatReadsOffBeforeItsTestsRefusesTheRun() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let device = Device(readings: ["1", "0"])
        let fake = Self.fake(root: root, device: device)

        let result = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events)).run()

        #expect(result.exitCode == 1)
        #expect(result.answer.contains("did not keep accessibility on"))
        #expect(!events.taken().contains("shards run"))
        #expect(TestRunTests.deleted(events.taken()).sorted() == [TestRunTests.firstUdid, TestRunTests.secondUdid].sorted())
    }

    /// A device read off just before its tests is written again, and a run whose next read is on goes ahead.
    @Test
    func aDeviceThatReadsOffThenOnRunsItsTests() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let device = Device(readings: ["1", "0", "1"])
        let fake = Self.fake(root: root, device: device)

        let result = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events)).run()

        #expect(!result.answer.contains("did not keep accessibility on"))
        #expect(events.taken().contains("shards run"))
        // Two keys at the boot and two again over the reading off before the tests.
        #expect(device.writes == 4)
    }

    /// A write that fails at the boot, with nothing ever read off, is a device nobody saw off: the run goes ahead.
    @Test
    func aFailedWriteAtBootWithNoOffReadingCarriesOn() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let device = Device(readings: ["1"], writesSucceed: false)
        let fake = Self.fake(root: root, device: device)

        let result = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events)).run()

        #expect(!result.answer.contains("did not keep accessibility on"))
        #expect(events.taken().contains("shards run"))
    }

    /// A cancellation that arrives during the check before the tests answers as the interruption and its exit code, not as an accessibility refusal.
    @Test
    func aCancellationDuringTheCheckAnswersAsTheInterruption() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let holder = Holder()
        let device = Device(readings: ["1", "0"])
        device.beforeRead = { count in
            // The first read is the boot's confirmation; the second is the check's.
            if count == 2 {
                holder.cancelFromAnotherThread(exitCode: 130)
            }
        }
        let fake = Self.fake(root: root, device: device)
        let run = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events))
        holder.put(run)

        let result = run.run()

        #expect(result.exitCode == 130)
        #expect(result.answer.contains("the run was interrupted"))
        #expect(!result.answer.contains("did not keep accessibility on"))
    }

    /// A cancellation during the check deletes every device, and the check answers the interruption at once rather than retrying writes on each device that is gone.
    @Test
    func aCancellationDuringTheCheckDoesNotWaitOnTheDeletedDevices() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let holder = Holder()
        let device = Device(readings: ["1", "0"])
        device.beforeRead = { count in
            // The first read is the boot's confirmation; the second is the check's.
            if count == 2 {
                holder.cancelFromAnotherThread(exitCode: 130)
            }
        }
        var fake = Self.fake(root: root, device: device)
        // A device the teardown deleted answers every spawn as simctl answers one it does not know.
        fake.accessibility = { arguments in
            let answer = device.answer(arguments)
            let udid = arguments.count > 2 ? arguments[2] : ""
            guard events.taken().contains("simctl delete \(udid)") else {
                return answer
            }
            return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "Invalid device: \(udid)\n")
        }
        let pausesAfterTheDelete = Counter()
        fake.pause = { _ in
            if TestRunTests.deleted(events.taken()).isEmpty == false {
                pausesAfterTheDelete.increment()
            }
        }
        let run = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events))
        holder.put(run)

        let result = run.run()

        #expect(result.exitCode == 130)
        #expect(result.answer.contains("the run was interrupted"))
        #expect(pausesAfterTheDelete.value <= 1)
    }

    /// A cancellation that lands on the check's read-back once the write's budget is spent, so the device reads off with no stop left to ask, answers as the interruption rather than as a device that did not keep accessibility on.
    @Test
    func aCancellationAtTheLastReadBackAnswersAsTheInterruption() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let holder = Holder()
        let ticks = TestRunTests.Ticks()
        let device = Device(readings: ["1", "0"])
        device.beforeRead = { count in
            // The second read is the check's own; the third is the read-back of its first write.
            if count == 3 {
                holder.cancelFromAnotherThread(exitCode: 130)
                ticks.advance(by: 3600)
            }
        }
        var fake = Self.fake(root: root, device: device)
        fake.waitClock = { ticks.next() }
        let run = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events))
        holder.put(run)

        let result = run.run()

        #expect(result.exitCode == 130)
        #expect(result.answer.contains("the run was interrupted"))
        #expect(!result.answer.contains("did not keep accessibility on"))
    }

    /// A cancellation that reaches the check on one device stops it before the next: the next device is not read or written, since the teardown has deleted it.
    @Test
    func aCancellationAtOneDevicesCheckLeavesTheNextDeviceUntouched() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let holder = Holder()
        let device = Device(readings: ["1", "0"])
        device.beforeRead = { count in
            // The first read is the boot's confirmation; the second is the check's on the first device.
            if count == 2 {
                holder.cancelFromAnotherThread(exitCode: 130)
            }
        }
        var fake = Self.fake(root: root, device: device)
        // Two test classes, so the plan has two shards and the check has a second device to visit.
        fake.tests = ["DemoUnitTests/CalculatorTests/t1()", "DemoUnitTests/OtherTests/t2()"]
        let touchesAfterTheDelete = Counter()
        fake.accessibility = { arguments in
            if arguments.count > 2, arguments[2] == TestRunTests.secondUdid, !TestRunTests.deleted(events.taken()).isEmpty {
                touchesAfterTheDelete.increment()
            }
            return device.answer(arguments)
        }
        let run = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events))
        holder.put(run)

        let result = run.run()

        #expect(result.exitCode == 130)
        #expect(touchesAfterTheDelete.value == 0)
    }

    /// A cancellation during the boot's arming ends the writing there: the device the teardown deleted is not retried for the rest of the confirmation budget, counted by the deleted device's own writes so the other device's pause cannot move it.
    @Test
    func aCancellationDuringTheBootDoesNotRetryWritesOnTheDeletedDevice() throws {
        let root = try TemporaryDirectory.make("test-run-accessibility")
        let events = TestRunTests.Recorder()
        let holder = Holder()
        let device = Device(readings: ["1"])
        var fake = Self.fake(root: root, device: device)
        let cancelled = Counter()
        let writesAfterTheDelete = Counter()
        fake.accessibility = { arguments in
            let udid = arguments.count > 2 ? arguments[2] : ""
            guard udid == TestRunTests.firstUdid, arguments.contains("write") else {
                return device.answer(arguments)
            }
            if TestRunTests.deleted(events.taken()).isEmpty == false {
                writesAfterTheDelete.increment()
            }
            // The first write of the boot's arming is where the cancel lands; from then on the device is gone.
            if cancelled.value == 0 {
                cancelled.increment()
                holder.cancelFromAnotherThread(exitCode: 130)
            }
            return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "Invalid device: \(udid)\n")
        }
        let run = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events))
        holder.put(run)

        let result = run.run()

        #expect(result.exitCode == 130)
        #expect(writesAfterTheDelete.value == 0)
    }
}

private extension TestRunAccessibilityTests {
    /// A run whose first device is `device`; the fake's clock for bounded waits ticks a second on every read, so a loop bounded by time ends.
    static func fake(root: URL, device: Device) -> TestRunTests.Fake {
        var fake = TestRunTests.Fake(root: root)
        fake.accessibility = { device.answer($0) }
        return fake
    }

    /// A count kept across threads.
    final class Counter: @unchecked Sendable {
        private let gate = NSLock()
        private var count = 0

        var value: Int {
            gate.withLock { count }
        }

        func increment() {
            gate.withLock { count += 1 }
        }
    }

    /// The first shard device's preference: the readings it answers in turn, the last repeating.
    ///
    /// Every write it was given is counted, and any other device reads on.
    final class Device: @unchecked Sendable {
        private let gate = NSLock()
        private var readings: [String]
        private let writesSucceed: Bool
        private var reads = 0
        private var written = 0
        var beforeRead: (@Sendable (Int) -> Void)?

        init(readings: [String], writesSucceed: Bool = true) {
            self.readings = readings
            self.writesSucceed = writesSucceed
        }

        var writes: Int {
            gate.withLock { written }
        }

        func answer(_ arguments: [String]) -> Subprocess.Output {
            guard arguments.count > 2, arguments[2] == TestRunTests.firstUdid else {
                return Subprocess.Output(succeeded: true, standardOutput: "1\n")
            }
            if arguments.contains("write") {
                gate.withLock { written += 1 }
                return Subprocess.Output(succeeded: writesSucceed, standardOutput: "", standardError: writesSucceed ? "" : "write failed\n")
            }
            let count = gate.withLock {
                reads += 1
                return reads
            }
            beforeRead?(count)
            let reading = gate.withLock { readings.count > 1 ? readings.removeFirst() : readings[0] }
            return Subprocess.Output(succeeded: true, standardOutput: "\(reading)\n")
        }
    }

    /// The one `TestRun` a cancelling seam has to reach, which does not exist yet when its environment is built.
    final class Holder: @unchecked Sendable {
        private let gate = NSLock()
        private var run: TestRun?

        func put(_ run: TestRun) {
            gate.withLock { self.run = run }
        }

        /// Cancels the run from a thread of its own and returns once the cancellation has finished.
        func cancelFromAnotherThread(exitCode: Int32) {
            let target = gate.withLock { run }
            let cancelled = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                target?.cancel(exitCode: exitCode)
                cancelled.signal()
            }
            cancelled.wait()
        }
    }
}
