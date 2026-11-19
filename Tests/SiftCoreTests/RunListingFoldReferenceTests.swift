//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Which earlier failure an excerpt's back-reference may name, and how it spells that failure's place.
@Suite(.temporaryDirectories)
struct RunListingFoldReferenceTests {
    /// A failure of another test listed between the reference and a later failure at the reference's place makes the reference ambiguous, so nothing folds.
    @Test
    func aFailureOfAnotherTestAtTheSamePlaceBetweenStopsTheFold() {
        let excerpt = ["one", "two", "three"]
        let block = RunListingFoldTests.listing([
            RunListingFoldTests.failure(named: "render()", at: "Helpers.swift:30:5", expecting: "first", beneath: excerpt),
            RunListingFoldTests.failure(named: "paint()", at: "Helpers.swift:30:5", expecting: "second", beneath: ["uno", "dos", "tres"]),
            RunListingFoldTests.failure(named: "render()", at: "Helpers.swift:31:5", expecting: "third", beneath: excerpt),
        ])

        #expect(block.count { $0 == "      three" } == 2)
        #expect(!block.contains { $0.contains("the same") })
    }

    /// A failure between them at another place leaves the fold standing.
    @Test
    func aFailureBetweenAtAnotherPlaceStillFolds() {
        let excerpt = ["one", "two", "three"]
        let block = RunListingFoldTests.listing([
            RunListingFoldTests.failure(named: "render()", at: "Helpers.swift:30:5", expecting: "first", beneath: excerpt),
            RunListingFoldTests.failure(named: "paint()", at: "Helpers.swift:35:5", expecting: "second", beneath: ["uno", "dos", "tres"]),
            RunListingFoldTests.failure(named: "render()", at: "Helpers.swift:31:5", expecting: "third", beneath: excerpt),
        ])

        #expect(block.contains("      (the same 3 lines as under the failure at Helpers.swift:30:5 above)"))
    }

    /// The reference is the nearest earlier excerpt printed in full: with excerpts E, F, E the third is not folded to the first.
    @Test
    func theReferenceIsTheNearestPrintedExcerptNotTheFirst() {
        let block = RunListingFoldTests.listing([
            RunListingFoldTests.failure(at: "GizmoTests.swift:12:9", expecting: "first", beneath: ["one", "two"]),
            RunListingFoldTests.failure(at: "GizmoTests.swift:13:9", expecting: "second", beneath: ["uno", "dos"]),
            RunListingFoldTests.failure(at: "GizmoTests.swift:14:9", expecting: "third", beneath: ["one", "two"]),
        ])

        #expect(block.count { $0 == "      two" } == 2)
        #expect(!block.contains { $0.contains("the same") })
    }

    /// An unlocated failure with an excerpt is the nearest printed one, but nothing folds to it.
    @Test
    func anUnlocatedReferenceIsNeverFoldedTo() {
        let block = RunListingFoldTests.listing([
            RunListingFoldTests.failure(at: nil, expecting: "first", beneath: ["one", "two"]),
            RunListingFoldTests.failure(at: "GizmoTests.swift:13:9", expecting: "second", beneath: ["one", "two"]),
        ])

        #expect(block.count { $0 == "      two" } == 2)
        #expect(!block.contains { $0.contains("the same") })
    }

    /// A reference at an absolute path is named as the answer spells paths.
    @Test
    func aReferenceAtAnAbsolutePathIsNamedByItsShortenedPath() {
        let block = RunFailureShape.of(
            [
                RunListingFoldTests.failure(at: "/Users/dev/Gizmo/Tests/GizmoTests.swift:12", expecting: "first", beneath: ["one", "two"]),
                RunListingFoldTests.failure(at: "/Users/dev/Gizmo/Tests/GizmoTests.swift:13", expecting: "second", beneath: ["one", "two"]),
            ],
            changedFiles: .of([]),
            paths: .read(in: URL(fileURLWithPath: "/Users/dev/Gizmo"))
        ).rendered()

        #expect(block.contains("      (the same 2 lines as under the failure at Tests/GizmoTests.swift:12 above)"))
    }

    /// A reference whose heading resolved to its test's own body is named without the `(body :…)` range.
    @Test
    func aResolvedReferenceIsNamedWithoutItsBodyRange() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.source, to: "Tests/GizmoTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "sources")
        try await SiftEngine(directory: root).ensureFresh()
        let locations = ["Tests/GizmoTests.swift:10:9", "Tests/GizmoTests.swift:11:9"]
        let sites = RunFailureSites.resolving(locations, inRepositoryAt: root)
        var filter = RunOutputFilter(invokedAs: ["swift", "test"])
        var log: [String] = []
        for location in locations {
            log += [
                "✘ Test check() recorded an issue at \(location): Expectation failed: Bool(false)",
                "↳ Bool(false) → false",
                "↳   output → \"one",
                "    two",
                "    three\"",
            ]
        }
        log.append("✘ Test run with 1 test in 1 suite failed after 0.010 seconds with 2 issues.")
        for line in log {
            filter.consume(line: line)
        }
        let answer = RunReportRenderer(kind: .swiftTest, workingDirectory: root, changedFiles: .of([]), sites: sites)
            .render(filter.finish(exitCode: 1), exitCode: 1, logURL: nil)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        #expect(answer.contains("  check() — Tests/GizmoTests.swift:10 (body :8-12)"))
        #expect(answer.contains("      (the same 2 lines as under the failure at Tests/GizmoTests.swift:10 above)"))
    }

    /// Cases that echo the same note but a different closest line are two values, so the line naming them says they differ.
    @Test
    func casesThatDifferOnlyInTheirClosestLineSayTheirValuesDiffer() {
        let failures = [1, 2].map { size in
            RunFailureShape.Failure(
                name: "fits(size:)",
                location: "GizmoTests.swift:20:9",
                message: "Expectation failed: gizmo.fits",
                arguments: "size → \(size)",
                note: "gizmo.fits → false",
                closestLine: "closest: gizmo \(size)"
            )
        }
        let block = RunListingFoldTests.listing(failures)

        #expect(block.contains("    … and 1 more case of this expectation: size → 2 (their values differ — see the raw log)"))
    }
}

private extension RunListingFoldReferenceTests {
    /// A `@Test func check()` on lines 8-12 that fails on lines 10 and 11.
    static var source: String {
        """
        //
        // Copyright © Agulhas Labs
        //

        import Testing

        struct GizmoTests {
            @Test
            func check() {
                #expect(Bool(false))
                #expect(Bool(false))
            }
        }

        """
    }
}
