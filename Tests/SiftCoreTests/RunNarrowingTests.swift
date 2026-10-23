//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Narrowness is read from a run's argv against a closed list, never from the space-joined key.
struct RunNarrowingTests {
    @Test(arguments: [
        ["swift", "test"],
        ["swift", "test", "--parallel", "-c", "debug"],
        ["swift", "test", "--num-workers", "4", "--scratch-path", "Gizmo Build"],
        ["xcodebuild", "-scheme", "Gizmo", "-destination", "platform=iOS Simulator,name=Widget", "-quiet", "test"],
    ])
    func closedListArgumentsAreUnnarrowed(arguments: [String]) {
        #expect(RunNarrowing.isUnnarrowed(arguments))
    }

    @Test(arguments: [
        ["swift", "test", "--filter", "GizmoTests"],
        ["swift", "test", "-c", "release"],
        ["swift", "test", "--package-path", "Gizmo"],
        ["xcodebuild", "-scheme", "Gizmo", "test", "-only-testing:GizmoTests"],
        ["make", "test"],
    ])
    func anythingElseNarrows(arguments: [String]) {
        #expect(!RunNarrowing.isUnnarrowed(arguments))
    }

    /// A recorded key that reads unnarrowed is still narrowed where its argv carries a filter, and one with no argv is narrowed.
    @Test
    func theArgvDecidesNotTheKey() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try CheckupFailedRunTests.ledger()
            let filtered = CheckupFailedRunTests.record(["swift", "test", "--filter", "GizmoTests"], ago: 60)
            ledger.record(RunLedger.Record(tree: filtered.tree, command: "swift test", toolchain: filtered.toolchain, finishedAt: filtered.finishedAt, log: nil, milliseconds: 1, workingDirectory: ".", arguments: filtered.arguments))

            let (findings, _) = try await CheckupFailedRunTests.check(ledger, roots: ["."])

            #expect(findings.map(\.findingClass) == [.unproved])
            #expect(!RunNarrowing.isUnnarrowed(nil))
        }
    }
}
