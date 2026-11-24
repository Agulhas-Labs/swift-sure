//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// A word-anchored sweep narrowed by `--exclude-dir` and `--exclude` is answered as `where` with every reference where the same sweep unnarrowed is not: the files the exclusions leave out are the ones no answer could account for.
@Suite(.temporaryDirectories)
struct GrepExcludeServedTests {
    /// A built package whose `Gadget` is referenced in source, with a prose file and a directory of files the index cannot account for beside it.
    private static func builtPackage() async throws -> URL {
        let root = try MCPTestRepo.make(declaring: "Alpha")
        let pallets = (1 ... 60).map { "func pallet\($0)(first: Gadget = Gadget(), second: Gadget = Gadget()) {}" }.joined(separator: "\n")
        try MCPTestRepo.add([
            "Package.swift": "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])\n",
            "Sources/App/Gadget.swift": "public struct Gadget {\n    public init() {}\n}\n",
            "Sources/App/Uses.swift": "struct Holder {\n    var gadget: Gadget\n    func make() -> Gadget { Gadget() }\n    func take(_ part: Gadget) {}\n}\n",
            "Sources/App/Stock/Aisles/Bays/Racks/Shelves/Pallets.swift": "\(pallets)\n",
            "Extra/Notes.txt": "Gadget is mentioned here\n",
            "Readme.md": "Gadget is documented here\n",
        ], to: root)
        try MCPTestRepo.build(root)
        try await SiftEngine(directory: root).ensureFresh()
        return root
    }

    /// Left bare, the sweep reaches files no `where` answer lists lines of and is left unchecked, not served as references; leaving them out with the flags the hook reads serves it.
    @Test
    func anExclusionTurnsAnUnprovableSweepIntoAServedReferenceAnswer() async throws {
        let root = try await Self.builtPackage()

        let bare = try await InPlaceAnswerTests.outcome("grep -rnw Gadget .", in: root)
        #expect(bare == .withheld(.unchecked), "\(bare)")

        let narrowed = try #require(try await InPlaceAnswerTests.answered("grep -rnw Gadget . --exclude-dir=.build --exclude-dir=Extra --exclude=*.md", in: root))

        #expect(narrowed.calls.map(\.tool) == ["where"])
        #expect(narrowed.reason.contains("`where Gadget (refs: true)`"))
    }
}
