//
// Copyright © Agulhas Labs
//

import Foundation

struct AffectedNameWalk {
    var reached: [TestSymbol: AffectedRenderer.Evidence] = [:]

    /// Every name carried into a scan, summed over the hops that ran — not the seed set, which is only the first of them.
    var scannedNames = 0

    var tooCommon: Set<String> = []

    /// The too-common names the walk followed only at sites qualified by their owner, each with one such spelling (`Gizmo.line`).
    ///
    /// Their bare, `Self.` and `x.` sites were dropped, so they are named in the answer as the names in ``tooCommon`` are.
    var ownerQualifiedOnly: [String: String] = [:]
    var capped = false

    /// Tests a name turned up in from a module that cannot load the module declaring the name, which the walk did not record.
    var setAside: Set<TestSymbol> = []

    /// The same note for the syntactic side, and printed in the same place — beside the resolved walk's, above the block that refers to both.
    func capNote(cap: Int) -> String? {
        capped ? "note: the name-matched fallback carried only \(cap) names into the next hop; the ones it dropped were not scanned" : nil
    }

    /// What the fallback has to say about itself, in the answer: that a name is not a symbol, and which names it threw away for being too common to mean anything.
    ///
    /// The two numbers are over one population by construction, which is the whole reason ``scannedNames`` counts per hop rather than once. Holding the seed count while `tooCommon` accumulated across every hop would let a `--depth 2` answer read "3 written names … were scanned" and, on the very next line, "10 names in that scan were … dropped" — ten out of three, in a command whose contract is that the reader can check its arithmetic against the limits block.
    func notes(cap: Int) -> [String] {
        guard scannedNames > 0 else { return [] }
        var lines = ["", "name-matched fallback: \(scannedNames) written name\(scannedNames == 1 ? "" : "s") \(scannedNames == 1 ? "was" : "were") scanned across the working tree instead — the base names of the declarations the store could not be asked about, and at each further hop the names of the declarations those turned up in. **A name is not a symbol** — same-named members of unrelated types are included, and dynamically dispatched uses are missed. Those tests are marked `name match` below."]
        lines.append(contentsOf: [tooCommonNote(cap: cap), ownerQualifiedNote(cap: cap), setAsideNote()].compactMap(\.self))
        return lines
    }

    /// What the after-edit walk (or, with no store, the call-site walk of every changed file) says of itself: what it was seeded from, and that a call site found by its written name is not a resolved reference.
    func afterEditNotes(_ seeds: AffectedAfterEditSeeds, cap: Int, noStore: Bool = false) -> [String] {
        let label = noStore ? "call-site walk" : "after-edit walk"
        let reason = seeds.headMovedSinceBuild ? "HEAD moved since the build" : "committed since the build"
        let sinceBuild = seeds.committedSinceBuild.isEmpty ? [] : ["", "\(label) — seeded whole: \(reason): \(seeds.committedSinceBuild.sorted().joined(separator: ", "))"]
        let refused = seeds.seededWhole.keys.sorted().map { "\(label) — seeded whole: \($0): \(seeds.seededWhole[$0, default: []].sorted().joined(separator: ", "))" }
        let commentOnly = seeds.commentOnly.isEmpty ? [] : ["", "\(label) — only comments changed, so nothing was walked from: \(seeds.commentOnly.sorted().joined(separator: ", "))"]
        let committed = sinceBuild + refused.flatMap { ["", $0] } + commentOnly
        guard !seeds.files.isEmpty else { return committed }
        let files = seeds.files.count
        let names = "\(seeds.nameCount) name\(seeds.nameCount == 1 ? "" : "s")"
        let note = "\(label) — syntactic, lower bound: the \(files) file\(files == 1 ? "" : "s") changed\(noStore ? "" : " since the build") \(files == 1 ? "was" : "were") seeded from the \(names) the diff touched there (\(seeds.namesListed)), not every declaration in \(files == 1 ? "it" : "them"), and followed to the call sites `where` finds by written name, \(scannedNames) name\(scannedNames == 1 ? "" : "s") over every hop. **A call site found by name is not a resolved reference** — same-named members of unrelated types are included, and dynamically dispatched uses are missed. Those tests are marked `name match` below, and a test the diff touched is listed itself."
        return ["", note] + committed + [tooCommonNote(cap: cap), ownerQualifiedNote(cap: cap), setAsideNote()].compactMap(\.self)
    }

    /// The names dropped for being written in more than `cap` files, named.
    func tooCommonNote(cap: Int) -> String? {
        guard !tooCommon.isEmpty else { return nil }
        let names = tooCommon.sorted()
        return "  \(names.count) name\(names.count == 1 ? "" : "s") in that scan \(names.count == 1 ? "was" : "were") written in more than \(cap) files and dropped rather than admitted — a match that broad narrows nothing, so NOTHING is reported for \(names.count == 1 ? "it" : "them"): \(names.joined(separator: ", "))"
    }

    /// The names followed only where their owning type qualifies them, with one example spelling: the sites written any other way were dropped, so nothing is reported through them.
    func ownerQualifiedNote(cap: Int) -> String? {
        guard !ownerQualifiedOnly.isEmpty else { return nil }
        let names = ownerQualifiedOnly.keys.sorted()
        let many = names.count != 1
        let example = ownerQualifiedOnly[names[0], default: ""]
        return "  \(names.count) name\(many ? "s" : "") in that scan \(many ? "were" : "was") written in more than \(cap) files and followed only where \(many ? "their types qualify them" : "its type qualifies it") (\(example)) — \(many ? "their" : "its") bare, Self. and x. sites were dropped, so NOTHING is reported through them: \(names.joined(separator: ", "))"
    }

    /// The line counting the tests set aside because their module cannot load the module declaring the name, with their targets named.
    func setAsideNote() -> String? {
        let unreached = setAside.filter { test in reached[test] == nil && !reached.keys.contains { $0.wholeSuiteRuns(test) } }
        guard !unreached.isEmpty else { return nil }
        let targets = Set(unreached.map(\.target)).sorted()
        let count = unreached.count
        return "  \(count) name-matched test\(count == 1 ? "" : "s") or suite\(count == 1 ? "" : "s") set aside in \(targets.joined(separator: ", ")): \(count == 1 ? "its" : "their") module cannot load the module declaring the name written there, since no import in it names that module or a tree module that loads it"
    }
}
