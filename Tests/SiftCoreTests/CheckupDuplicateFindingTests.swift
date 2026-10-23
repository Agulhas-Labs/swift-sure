//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// The `duplicate` outcome as built from `dupes`' answer: one finding per group, at the seed, naming the closest partner.
struct CheckupDuplicateFindingTests {
    private static func outcome(_ fingerprints: [DeclarationFingerprint], seeded: [DeclarationFingerprint]) -> CheckupOutcome {
        let seeds = Set(seeded.map(DupesSeedTests.key))
        return CheckupDuplicateCheck.outcome(answer: DupesSeedTests.answer(fingerprints, seeds: seeds), seeds: seeds)
    }

    @Test
    func aGroupIsOneFindingAtTheSeedNamingThePartner() throws {
        let (depot, orchard) = (DupesSeedTests.fingerprint("Depot"), DupesSeedTests.fingerprint("Orchard"))
        let found = Self.outcome([depot, orchard], seeded: [orchard])
        let finding = try #require(found.findings.first)

        #expect(found.findings.count == 1)
        #expect(finding.findingClass == .duplicate)
        #expect(finding.location == "Sources/Depot/Orchard.swift:1-6")
        #expect(finding.text == "Orchard.run and Depot.run at Sources/Depot/Depot.swift:1-6 clear both gates (1.00)")
        #expect(finding.command == "\(ProductName.current.binary) similar Orchard.run")
        #expect(found.status == .checked(basis: nil, bound: nil))
    }

    @Test
    func whereBothSidesAreSeedsTheFirstInPathOrderIsTheFinding() {
        let (depot, orchard) = (DupesSeedTests.fingerprint("Depot"), DupesSeedTests.fingerprint("Orchard"))
        let found = Self.outcome([depot, orchard], seeded: [depot, orchard])

        #expect(found.findings.count == 1)
        #expect(found.findings.first?.location == "Sources/Depot/Depot.swift:1-6")
    }

    @Test
    func groupsPastTheCapAreCountedOnTheBound() {
        let pairs = (0 ..< 12).flatMap { index in
            let callees = (1 ... 8).map { "group\(index)rare\($0)" }
            return [
                DupesSeedTests.fingerprint("Left\(index)", callees: callees),
                DupesSeedTests.fingerprint("Right\(index)", callees: callees),
            ]
        }
        let seeded = pairs.filter { $0.declaration.qualifiedName.hasPrefix("Left") }
        let found = Self.outcome(pairs, seeded: seeded)

        #expect(found.findings.count == SimilarityScore.resultCap)
        #expect(found.status == .checked(basis: nil, bound: "2 more past the cap"))
    }

    @Test
    func aRangeWithNoSeedingDeclarationIsNotChecked() {
        #expect(CheckupDuplicateCheck.unseeded.status == .notChecked(reason: "no added or body-changed declaration"))
        #expect(CheckupDuplicateCheck.unseeded.check == .duplicates)
    }

    @Test
    func duplicateFindingsSortAfterFlakyOnes() throws {
        let (depot, orchard) = (DupesSeedTests.fingerprint("Depot"), DupesSeedTests.fingerprint("Orchard"))
        let duplicate = try #require(Self.outcome([depot, orchard], seeded: [orchard]).findings.first)
        let flaky = CheckupFinding(findingClass: .flaky, path: nil, line: nil, endLine: nil, text: "spin failed and passed", command: "swift-sure flakes spin")
        let lines = CheckupRenderer(header: "tree: app", range: "main...HEAD", changedFiles: 2, findings: [duplicate, flaky], checks: .unbuilt, offset: 0)
            .render()
            .split(separator: "\n")
            .map(String.init)
        let classes = lines.compactMap { line in ["flaky", "duplicate"].first { line.hasPrefix($0 + " ") } }

        #expect(classes == ["flaky", "duplicate"])
    }
}
