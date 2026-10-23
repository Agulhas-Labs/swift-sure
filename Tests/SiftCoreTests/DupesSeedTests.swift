//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// A seed set limits which pairs are proposed to those with a seed on one side; the gates, scoring and census are the unseeded ones.
struct DupesSeedTests {
    static let rare = (1 ... 8).map { "rare\($0)" }

    static func fingerprint(_ name: String, path: String? = nil, callees: [String] = rare) -> DeclarationFingerprint {
        DupesChainedGroupTests.fingerprint(name, callees: callees, path: path)
    }

    static func key(_ fingerprint: DeclarationFingerprint) -> DupesSeedKey {
        DupesSeedKey(path: fingerprint.declaration.path, line: fingerprint.declaration.line)
    }

    static func answer(_ fingerprints: [DeclarationFingerprint], seeds: Set<DupesSeedKey>?) -> DupesAnswer {
        DupesSearch.answer(scope: [], fingerprints: fingerprints + DupesChainedGroupTests.filler, filesScanned: 30, options: DupesOptions(seeds: seeds))
    }

    @Test
    func noSeedsIsTheUnseededAnswer() {
        let pair = [Self.fingerprint("Depot"), Self.fingerprint("Orchard")]
        let plain = DupesSearch.answer(scope: [], fingerprints: pair + DupesChainedGroupTests.filler, filesScanned: 30)
        let unseeded = Self.answer(pair, seeds: nil)

        #expect(unseeded.census == plain.census)
        #expect(unseeded.totalGroups == plain.totalGroups)
        #expect(unseeded.groups.map { $0.members.map(\.declaration.qualifiedName) } == plain.groups.map { $0.members.map(\.declaration.qualifiedName) })
        #expect(plain.totalGroups == 1)
    }

    @Test
    func oneSeededSideFindsThePair() {
        let (depot, orchard) = (Self.fingerprint("Depot"), Self.fingerprint("Orchard"))

        #expect(Self.answer([depot, orchard], seeds: [Self.key(depot)]).totalGroups == 1)
        #expect(Self.answer([depot, orchard], seeds: [Self.key(orchard)]).totalGroups == 1)
    }

    @Test
    func neitherSideSeededFindsNothingAndTheCensusIsUnchanged() {
        let (depot, orchard, gizmo) = (Self.fingerprint("Depot"), Self.fingerprint("Orchard"), Self.fingerprint("Gizmo", callees: ["solo1", "solo2", "solo3"]))
        let seeded = Self.answer([depot, orchard, gizmo], seeds: [Self.key(gizmo)])
        let plain = Self.answer([depot, orchard, gizmo], seeds: nil)

        #expect(seeded.totalGroups == 0)
        #expect(seeded.census == plain.census)
        #expect(Self.answer([depot, orchard], seeds: []).totalGroups == 0)
    }

    @Test
    func aSeedThatIsTestCodeProposesNothing() {
        let testCopy = Self.fingerprint("Depot", path: "Tests/Depot/Gizmo.swift")
        let production = Self.fingerprint("Orchard")
        let found = Self.answer([testCopy, production], seeds: [Self.key(testCopy)])

        #expect(Self.answer([testCopy, production], seeds: nil).totalGroups == 1)
        #expect(found.totalGroups == 0)
    }

    /// Seeding one of three copies proposes its two pairs; the pair between the other two is not proposed, so complete linkage leaves a group of two.
    @Test
    func seedingOneOfThreeCopiesKeepsItsPairs() {
        let (depot, orchard, catalogue) = (Self.fingerprint("Depot"), Self.fingerprint("Orchard"), Self.fingerprint("Catalogue"))
        let plain = Self.answer([depot, orchard, catalogue], seeds: nil)
        let seeded = Self.answer([depot, orchard, catalogue], seeds: [Self.key(depot)])

        #expect(plain.groups.map(\.members.count) == [3])
        #expect(seeded.groups.map(\.members.count) == [2])
        #expect(seeded.groups.first?.members.contains { $0.declaration.qualifiedName == "Depot.run" } == true)
    }
}
