//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Which declarations of a change seed the `duplicate` check, and what a finding says.
struct CheckupDuplicateSeedTests {
    private static var path: String {
        "Sources/App/Gizmo.swift"
    }

    private static func body(_ calls: [String], attribute: String = "") -> String {
        let lines = calls.map { "        \($0)()" }.joined(separator: "\n")
        return "struct Gizmo {\n\(attribute)    func wobble() {\n\(lines)\n    }\n}\n"
    }

    private static func diff(old: String?, new: String) -> FileDiff {
        FileDiff.compare(path: path, status: old == nil ? .added : .modified, lineStat: nil, bytes: (old?.data(using: .utf8), new.data(using: .utf8)))
    }

    private static func seeds(old: String?, new: String) -> Set<DupesSeedKey> {
        CheckupDuplicateCheck.seeds(in: [diff(old: old, new: new)], fingerprints: FingerprintScanner.fingerprints(in: new, path: path))
    }

    private static var calls: [String] {
        ["alpha", "beta", "gamma", "delta"]
    }

    @Test
    func aBodyChangedDeclarationIsASeedAndAnUntouchedOneIsNot() {
        let old = Self.body(Self.calls) + "struct Widget {\n    func spin() {\n        one()\n        two()\n        three()\n        four()\n    }\n}\n"
        let new = Self.body(Self.calls + ["epsilon"]) + "struct Widget {\n    func spin() {\n        one()\n        two()\n        three()\n        four()\n    }\n}\n"
        let found = Self.seeds(old: old, new: new)

        #expect(found == [DupesSeedKey(path: Self.path, line: 2)])
    }

    @Test
    func anUnchangedFileSeedsNothing() {
        let source = Self.body(Self.calls)

        #expect(Self.seeds(old: source, new: source).isEmpty)
        #expect(!CheckupDuplicateCheck.hasSeeds(in: [Self.diff(old: source, new: source)]))
    }

    @Test
    func everyMemberOfAWhollyAddedTypeIsASeed() {
        let new = Self.body(Self.calls).replacingOccurrences(of: "}\n}\n", with: "}\n    func spin() {\n        one()\n        two()\n        three()\n        four()\n    }\n}\n")
        let found = Self.seeds(old: nil, new: new)

        #expect(found.map(\.line).sorted() == [2, 8])
    }

    @Test
    func anAttributeOnItsOwnLineStillSeedsTheDeclaration() {
        let old = Self.body(Self.calls, attribute: "    @MainActor\n")
        let new = Self.body(Self.calls + ["epsilon"], attribute: "    @MainActor\n")

        #expect(Self.seeds(old: old, new: new).count == 1)
    }

    @Test
    func aCommentBetweenDeclarationsIsNotASeed() {
        let old = "struct Gizmo {\n    func wobble() {\n        alpha()\n    }\n}\n"
        let new = "struct Gizmo {\n    func wobble() {\n        alpha()\n    }\n    // a note\n}\n"

        #expect(Self.seeds(old: old, new: new).isEmpty)
    }
}
