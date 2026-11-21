//
// Copyright © Agulhas Labs
//

import Foundation

/// The test files no store holds a unit for, and what the answer says of them: the store records no reference from a target it never compiled, so its answer is a lower bound and those files are name-matched instead.
struct AffectedUnbuiltTestFiles {
    var paths: [String] = []

    /// The test files another project in the tree holds, after a test build ran: no build of the store's project compiles them, so they are counted on one line and never walked, since their tests would land in runner lines naming a target that build does not have.
    var outsideTargets: [String] = []

    var provenance: DiscoveredStore.Provenance?
    var package = ""
    /// The root flag the build command carries (``StoreRemedy/rootFlag(root:currentDirectory:)``).
    var rootFlag = ""

    /// The one note saying so, with the build that adds them where it is known: SwiftPM's own store, since a plain `swift build` builds no test target.
    func notes(walk: AffectedNameWalk, cap: Int) -> [String] {
        var outside: [String] = []
        if !outsideTargets.isEmpty {
            let them = outsideTargets.count == 1 ? "it" : "them"
            outside = ["", "\(TestFileCoverage.outsideTargets(outsideTargets.count)): no build of the store's project compiles \(them), so no test in \(them) was matched"]
        }
        guard !paths.isEmpty else { return outside }
        let count = paths.count
        let build = provenance == .swiftPMBuild ? "build \(count == 1 ? "it" : "them") with `\(DiscoveredStore.swiftPMBuildCommand(package: package, buildTests: true, rootFlag: rootFlag))`" : "build \(count == 1 ? "its" : "their") target"
        let names = "\(walk.scannedNames) written name\(walk.scannedNames == 1 ? "" : "s")"
        var lines = [
            "",
            "test files without a unit: \(count) test file\(count == 1 ? " has" : "s have") no unit in the store, so it records no reference from \(count == 1 ? "it" : "them") — \(build); until then the tests there were matched by \(names) of the declarations it did answer for, and are marked `name match` below. **A name is not a symbol** — same-named members of unrelated types are included, and dynamically dispatched uses are missed.",
        ]
        if !walk.tooCommon.isEmpty {
            let dropped = walk.tooCommon.sorted()
            lines.append("  \(dropped.count) name\(dropped.count == 1 ? "" : "s") in that scan \(dropped.count == 1 ? "was" : "were") written in more than \(cap) files and dropped, so NOTHING is reported for \(dropped.count == 1 ? "it" : "them"): \(dropped.joined(separator: ", "))")
        }
        lines.append(contentsOf: [walk.ownerQualifiedNote(cap: cap), walk.setAsideNote()].compactMap(\.self))
        return lines + outside
    }
}
