//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// Covers which `.xctestrun` a run's enumeration and shards use, and the note saying whether animations are off, through the seam that makes the copy.
@Suite(.temporaryDirectories)
struct TestRunAnimationsTests {
    /// A run over the shared fake, with the animations seam replaced and every shard's argv recorded as a line of its own.
    private func run(
        in root: URL,
        request: TestRunRequest? = nil,
        enumerating: (@Sendable () -> Void)? = nil,
        tests: [String]? = nil,
        holder: TestRunTests.RunHolder? = nil,
        accessibility: (@Sendable ([String]) -> Subprocess.Output)? = nil,
        seam: @escaping @Sendable (URL, URL) throws -> URL?
    ) -> Outcome {
        let events = TestRunTests.Recorder()
        var fake = TestRunTests.Fake(root: root)
        fake.shards = { assignments in
            for assignment in assignments {
                events.append("shard argv: " + assignment.argv.joined(separator: " "))
            }
            return assignments.map { _ in ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 0, wallSeconds: 1, logPath: "/dev/null") }
        }
        fake.xctestrunWithAnimationsOff = seam
        fake.whileEnumerating = enumerating
        fake.accessibility = accessibility
        if let tests {
            fake.tests = tests
        }
        let environment = fake.environment(events)
        let testRun = TestRun(request: request ?? TestRunTests.request(in: root), environment: environment)
        holder?.put(testRun)
        let result = testRun.run()
        let launches = events.launches().map { $0.joined(separator: " ") }
        let enumeration = launches.first { $0.contains("-enumerate-tests") } ?? ""
        let shards = events.taken().filter { $0.hasPrefix("shard argv: ") }
        return Outcome(answer: result.answer, enumeration: enumeration, shards: shards)
    }

    private static let copyName = "copy-\(TestRunTests.Fake.xctestrunName)"

    /// A copy the seam returns is what the enumeration and every shard run from, and the answer says animations are off.
    @Test
    func aCopyIsWhatTheEnumerationAndTheShardsRunFromAndTheAnswerSaysSo() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let copy = root.appendingPathComponent(Self.copyName)

        let outcome = run(in: root) { _, _ in copy }

        #expect(outcome.enumeration.contains("-xctestrun \(copy.path)"))
        #expect(!outcome.shards.isEmpty)
        #expect(outcome.shards.allSatisfy { $0.contains("-xctestrun \(copy.path)") })
        #expect(outcome.answer.contains(TestRun.animationsOffNote))
    }

    /// The seam is handed the original and the run's own directory, so the copy goes with the run.
    @Test
    func theSeamIsHandedTheOriginalAndTheRunsDirectory() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let handed = Handed()

        _ = run(in: root) { original, directory in
            handed.put(original: original, directory: directory)
            return nil
        }

        let seen = try #require(handed.taken())

        #expect(seen.0.lastPathComponent == TestRunTests.Fake.xctestrunName)
        #expect(seen.1.path.contains("/.swift-sure/shards/"))
    }

    /// No UI target means no copy: the original runs and the answer says nothing about animations.
    @Test
    func noCopyLeavesTheOriginalInArgvAndSaysNothing() throws {
        let root = try TemporaryDirectory.make("test-run-animations")

        let outcome = run(in: root) { _, _ in nil }

        #expect(outcome.enumeration.contains(TestRunTests.Fake.xctestrunName))
        #expect(!outcome.enumeration.contains(Self.copyName))
        #expect(!outcome.shards.isEmpty)
        #expect(outcome.shards.allSatisfy { $0.contains(TestRunTests.Fake.xctestrunName) && !$0.contains(Self.copyName) })
        #expect(!outcome.answer.contains("animations:"))
    }

    /// A library that cannot be used leaves the original running and says why animations are on.
    @Test
    func aSeamThatThrowsKeepsTheOriginalAndNamesTheError() throws {
        let root = try TemporaryDirectory.make("test-run-animations")

        let outcome = run(in: root) { _, _ in throw Refused() }

        #expect(outcome.enumeration.contains(TestRunTests.Fake.xctestrunName))
        #expect(!outcome.shards.isEmpty)
        #expect(outcome.shards.allSatisfy { $0.contains(TestRunTests.Fake.xctestrunName) })
        #expect(outcome.answer.contains("animations: on, since the library that switches them off could not be used: the compiler said no"))
    }

    /// An enumeration of the copy that is refused still ends with the note, so the answer says the copy ran and `--animations` is the way out.
    @Test
    func aRefusedEnumerationOfTheCopyEndsWithTheNote() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let copy = root.appendingPathComponent(Self.copyName)

        let outcome = run(in: root, enumerating: {}, seam: { _, _ in copy })

        #expect(outcome.enumeration.contains("-xctestrun \(copy.path)"))
        #expect(outcome.shards.isEmpty)
        #expect(outcome.answer.contains(TestRun.animationsOffNote))
    }

    /// A copy whose enumeration finds no tests still ends with the note.
    @Test
    func anEmptyEnumerationOfTheCopyEndsWithTheNote() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let copy = root.appendingPathComponent(Self.copyName)

        let outcome = run(in: root, tests: []) { _, _ in copy }

        #expect(outcome.answer.contains("the plan enumerated no tests"))
        #expect(outcome.shards.isEmpty)
        #expect(outcome.answer.contains(TestRun.animationsOffNote))
    }

    /// A device whose boot cannot confirm accessibility ends the run after the copy was enumerated, and the answer still carries the note, once.
    @Test
    func aProvisioningFailureAfterTheCopyEndsWithTheNoteOnce() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let copy = root.appendingPathComponent(Self.copyName)

        let outcome = run(
            in: root,
            accessibility: { arguments in
                arguments.contains("write")
                    ? Subprocess.Output(succeeded: false, standardOutput: "", standardError: "write failed\n")
                    : Subprocess.Output(succeeded: true, standardOutput: "0\n")
            },
            seam: { _, _ in copy }
        )

        #expect(outcome.answer.hasPrefix("✘ swift-sure test"))
        #expect(outcome.shards.isEmpty)
        #expect(outcome.answer.components(separatedBy: TestRun.animationsOffNote).count == 2)
    }

    /// A device that reads accessibility off before its tests ends the run after the copy was enumerated, and the answer still carries the note, once.
    @Test
    func aFailedAccessibilityConfirmationAfterTheCopyEndsWithTheNoteOnce() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let copy = root.appendingPathComponent(Self.copyName)
        let readings = Readings(["1", "0"])

        let outcome = run(
            in: root,
            accessibility: { arguments in
                guard arguments.contains("read") else {
                    return Subprocess.Output(succeeded: true, standardOutput: "")
                }
                return Subprocess.Output(succeeded: true, standardOutput: "\(readings.next())\n")
            },
            seam: { _, _ in copy }
        )

        #expect(outcome.answer.contains("did not keep accessibility on"))
        #expect(outcome.shards.isEmpty)
        #expect(outcome.answer.components(separatedBy: TestRun.animationsOffNote).count == 2)
    }

    /// An interruption during the enumeration of the copy gets no note, because the run was not ended by anything the note explains.
    @Test
    func anInterruptionDuringTheEnumerationOfTheCopyGetsNoNote() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let copy = root.appendingPathComponent(Self.copyName)
        let holder = TestRunTests.RunHolder()

        let outcome = run(
            in: root,
            enumerating: { holder.cancelFromAnotherThread(exitCode: 128 + SIGINT) },
            holder: holder,
            seam: { _, _ in copy }
        )

        #expect(outcome.enumeration.contains("-xctestrun \(copy.path)"))
        #expect(outcome.answer.contains("the run was interrupted"))
        #expect(!outcome.answer.contains("animations:"))
    }

    /// The library's own error is named by its description, not by the system's generic sentence.
    @Test
    func aLibraryThatCouldNotBeBuiltNamesItsDetailInTheNote() throws {
        let root = try TemporaryDirectory.make("test-run-animations")

        let outcome = run(in: root) { _, _ in throw AnimationsOffError.libraryNotBuilt("a.m:1:1: error: boom") }

        #expect(outcome.answer.contains("animations: on, since the library that switches them off could not be used: the animations-off library could not be built: a.m:1:1: error: boom"))
        #expect(!outcome.answer.contains("The operation couldn't be completed"))
    }

    /// `--animations` never reaches for the library, and its rerun line carries the flag.
    @Test
    func animationsOnNeverCallsTheSeamAndTheRerunPrefixCarriesTheFlag() throws {
        let root = try TemporaryDirectory.make("test-run-animations")
        let calls = Handed()
        let request = TestRunRequest(
            scheme: "TestDemo",
            deviceTypeName: "iPhone 17",
            requestedShards: 2,
            workingDirectory: root,
            repositoryRoot: root,
            executable: root.appendingPathComponent("swift-sure"),
            animations: true
        )

        let outcome = run(in: root, request: request) { original, directory in
            calls.put(original: original, directory: directory)
            return nil
        }

        #expect(calls.taken() == nil)
        #expect(!outcome.answer.contains("animations:"))
        #expect(request.rerunCommandPrefix.hasSuffix(" --animations"))
        #expect(!TestRunTests.request(in: root).rerunCommandPrefix.contains("--animations"))
    }
}

extension TestRunAnimationsTests {
    struct Refused: LocalizedError {
        let errorDescription: String? = "the compiler said no"
    }

    /// Readings answered in turn, the last repeating.
    final class Readings: @unchecked Sendable {
        private let gate = NSLock()
        private var values: [String]

        init(_ values: [String]) {
            self.values = values
        }

        func next() -> String {
            gate.withLock { values.count > 1 ? values.removeFirst() : values[0] }
        }
    }

    /// What a run answered, the enumeration's command line and each shard's.
    struct Outcome {
        let answer: String
        let enumeration: String
        let shards: [String]
    }

    /// What the seam was handed, if it was called.
    final class Handed: @unchecked Sendable {
        private let gate = NSLock()
        private var value: (URL, URL)?

        func put(original: URL, directory: URL) {
            gate.withLock { value = (original, directory) }
        }

        func taken() -> (URL, URL)? {
            gate.withLock { value }
        }
    }
}
