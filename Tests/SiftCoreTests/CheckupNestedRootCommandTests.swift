//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A command the `test runs` check suggests runs in the package root it names, and a narrowed command is named by its flags counted.
struct CheckupNestedRootCommandTests {
    @Test
    func aNestedRootsSuggestionRunsInItsDirectoryFromTheRepositoryRoot() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try CheckupFailedRunTests.ledger()
            ledger.record(CheckupFailedRunTests.record(["swift", "test", "--filter", "A"], ago: 60, workingDirectory: "Sub"))

            let (findings, _) = try await CheckupFailedRunTests.check(ledger, roots: ["Sub"])

            #expect(findings.first?.text.contains(" from Sub") == true)
            #expect(findings.first?.command == "\(ProductName.current.binary) run --root Sub -- swift test")
        }
    }

    @Test
    func aRerunOfARedFromANestedRootRunsInItsDirectory() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try CheckupFailedRunTests.ledger()
            ledger.failedRuns.record(CheckupFailedRunTests.record(["swift", "test", "--filter", "A"], ago: 30, workingDirectory: "Gizmo Sub", exitCode: 1))

            let (findings, _) = try await CheckupFailedRunTests.check(ledger, roots: ["Gizmo Sub"])

            let failed = try #require(findings.first { $0.findingClass == .failed })
            #expect(failed.command == "\(ProductName.current.binary) run --root 'Gizmo Sub' -- swift test --filter A")
        }
    }

    @Test
    func aNarrowedCommandIsNamedByItsFlagsCounted() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try CheckupFailedRunTests.ledger()
            let filters = (1 ... 15).flatMap { ["--filter", "GizmoTests\($0)"] }
            ledger.record(CheckupFailedRunTests.record(["swift", "test"] + filters + ["--skip", "Slow"], ago: 180))

            let (findings, _) = try await CheckupFailedRunTests.check(ledger, roots: ["."])

            #expect(findings.first?.text.contains("(not counting: swift test --filter ×15 --skip, narrowed, 3m ago)") == true)
        }
    }

    @Test
    func aSingleFlagCarriesNoCount() {
        #expect(RunNarrowing.summary(["swift", "test", "--filter=A"]) == "swift test --filter")
        #expect(RunNarrowing.summary(["xcodebuild", "-scheme", "Gizmo", "test", "-only-testing:A", "-only-testing:B"]) == "xcodebuild -scheme Gizmo test -only-testing ×2")
        #expect(RunNarrowing.summary(["make", "test"]) == nil)
    }
}
