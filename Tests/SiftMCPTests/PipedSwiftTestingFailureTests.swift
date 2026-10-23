//
// Copyright © Agulhas Labs
//

import SiftMCP
import Testing

/// A piped test run whose output shows a Swift Testing failure line is named after it ran, also when other commands share its line.
struct PipedSwiftTestingFailureTests {
    private static var output: String {
        """
        ✔ Test run with 26 tests in 3 suites passed after 0.012 seconds.
        ✘ Test "Decodes escapes, so a user ID containing a colon displays" recorded an issue at GizmoTests.swift:68:9: Expectation failed: key.name == "Dept: Ops"
        ✘ Test "Parses a listing into keys" recorded an issue at GizmoTests.swift:18:9: Expectation failed: ada.fingerprint == "AAAA"
        """
    }

    private static var compound: String {
        #"git stash -q && swift test --package-path DepotKit 2>&1 | grep -E "^✘|Test run with|issue" | head; git stash pop -q; git status --short"#
    }

    @Test func aFailureLineBehindAPassingTallyNamesTheWrappedRun() {
        let note = PipedBuildFailure.note(for: #"swift test 2>&1 | grep -E "^✘|Test run with" | head"#, output: Self.output)

        #expect(note == "swift-sure: this piped test run failed. `swift-sure run -- swift test` lists each failure once by signature and keeps the full log under .swift-sure/runs/.")
    }

    @Test func aStashBeforeThePipelineStillNamesTheBuild() {
        let note = PipedBuildFailure.note(for: Self.compound, output: Self.output)

        #expect(note == "swift-sure: this piped test run failed. `swift-sure run -- swift test --package-path DepotKit` lists each failure once by signature and keeps the full log under .swift-sure/runs/.")
    }

    @Test func aDirectoryChangeBeforeAStashIsKept() throws {
        let note = try #require(PipedBuildFailure.note(for: "cd DepotKit && git stash -q && swift test 2>&1 | head; git stash pop -q", output: Self.output))

        #expect(note.contains("`cd DepotKit && swift-sure run -- swift test`"))
    }

    @Test func aKnownIssueIsNoFailure() {
        let output = """
        ✔ Test run with 26 tests in 3 suites passed after 0.012 seconds.
        ✘ Test "Parses a listing" recorded a known issue at GizmoTests.swift:18:9: Expectation failed: ada.fingerprint == "AAAA"
        """

        #expect(PipedBuildFailure.note(for: #"swift test 2>&1 | grep -E "^✘|Test run with" | head"#, output: output) == nil)
    }

    @Test func twoBuildsInTwoStatementsNameNothing() {
        #expect(PipedBuildFailure.note(for: "swift build | tail -3; swift test | tail -3", output: Self.output) == nil)
    }

    private static var passing: String {
        "✔ Test run with 26 tests in 3 suites passed after 0.012 seconds."
    }

    private static var failure: String {
        "✘ Test \"Parses a listing\" recorded an issue at GizmoTests.swift:18:9: Expectation failed"
    }

    @Test func aCommitLogBesideAPassingRunNamesNothing() {
        let output = "\(Self.passing)\n    \(Self.failure)"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -1; git log -1", output: output) == nil)
    }

    @Test func aDiffBesideAPassingRunNamesNothing() {
        let output = "\(Self.passing)\n+        \(Self.failure)"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -1; git diff", output: output) == nil)
    }

    @Test func aShownCommitBesideAPassingBuildNamesNothing() {
        let output = "Build complete! (1.20s)\n+    Test x() failed after 1 seconds"

        #expect(PipedBuildFailure.note(for: "swift build 2>&1 | tail -1; git show HEAD", output: output) == nil)
    }

    @Test func anEchoBesideAPassingRunNamesNothing() {
        let output = "\(Self.passing)\n✘ Test x() failed after 1 seconds"

        #expect(PipedBuildFailure.note(for: #"swift test 2>&1 | tail -1; echo "✘ Test x() failed after 1 seconds""#, output: output) == nil)
    }

    @Test func aStatusListingBesideAFailingRunStillNamesIt() {
        let output = "\(Self.passing)\n\(Self.failure)"
        let note = PipedBuildFailure.note(for: "swift test 2>&1 | tail -3; git status --short", output: output)

        #expect(note?.contains("`swift-sure run -- swift test`") == true)
    }

    @Test func aStashDiffBesideAPassingRunNamesNothing() {
        let output = "\(Self.passing)\n+** TEST FAILED **"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -1; git stash show -p", output: output) == nil)
    }

    @Test func aStashDiffBesideAPassingBuildNamesNothing() {
        let output = "Build complete! (1.20s)\n+** BUILD FAILED **"

        #expect(PipedBuildFailure.note(for: "swift build 2>&1 | tail -1; git stash show -p", output: output) == nil)
    }

    @Test func aVerboseStatusBesideAPassingRunNamesNothing() {
        let output = "\(Self.passing)\n+error: Process '/x/xctest' exited with unexpected signal code 11"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -1; git status -v", output: output) == nil)
    }

    @Test func aVerboseStatusBesideAPassingBuildNamesNothing() {
        let output = "0\n+Sources/Gizmo.swift:3:5: error: cannot find 'x' in scope"

        #expect(PipedBuildFailure.note(for: "swift build 2>&1 | grep -c warning; git status -v", output: output) == nil)
    }

    @Test func aStashListBesideAFailingRunNamesNothing() {
        let output = "\(Self.passing)\n\(Self.failure)"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -3; git stash list", output: output) == nil)
    }

    @Test func aBranchListBesideAFailingRunNamesNothing() {
        let output = "\(Self.passing)\n\(Self.failure)"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -3; git branch", output: output) == nil)
    }

    @Test func aDirectoryListingBesideAFailingRunNamesNothing() {
        let output = "\(Self.passing)\n\(Self.failure)"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -3; ls", output: output) == nil)
    }

    @Test func aQuietStashBesideAFailingRunStillNamesIt() {
        let output = "\(Self.passing)\n\(Self.failure)"
        let note = PipedBuildFailure.note(for: "swift test 2>&1 | tail -3; git stash -q", output: output)

        #expect(note?.contains("`swift-sure run -- swift test`") == true)
    }

    @Test func anIndentedFailureLineInTheRunsOwnOutputNamesNothing() {
        let output = "    ✘ Test x() recorded an issue at Gizmo.swift:3:5: Expectation failed\n\(Self.passing)"

        #expect(PipedBuildFailure.note(for: "swift test 2>&1 | tail -2", output: output) == nil)
    }

    @Test func aDirectoryChangeAfterAStashHasNoLeadingBlank() throws {
        let output = "\(Self.passing)\n\(Self.failure)"
        let note = try #require(PipedBuildFailure.note(for: "git stash && cd GizmoKit && swift test 2>&1 | tail -3", output: output))

        #expect(note.contains("`cd GizmoKit && swift-sure run -- swift test`"))
    }
}
