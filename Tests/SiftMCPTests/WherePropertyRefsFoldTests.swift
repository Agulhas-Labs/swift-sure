//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
@testable import SiftMCP
import Testing

/// A property's, a subscript's or an enum case's `--refs` answer lists each reference line once: `references to` is folded against the `reads and writes of` or `uses of` section above it, as a function's is against `callers of` (Docs/Design.md §2, *The callers/references fold*).
@Suite(.temporaryDirectories)
struct WherePropertyRefsFoldTests {
    private static var gizmo: String {
        "public struct Gizmo {\n    public var count = 0\n    public init() {}\n    public func ping() {}\n}\n\npublic enum Widget {\n    case idle\n    case busy\n}\n"
    }

    private static var gadget: String {
        "func bump(_ gizmo: inout Gizmo) {\n    gizmo.count += 1\n    _ = gizmo.count\n    gizmo.ping()\n}\n\nfunc reset(_ gizmo: inout Gizmo) {\n    gizmo.count = 0\n}\n\nfunc park() -> Widget {\n    .busy\n}\n\nfunc settle(_ widget: Widget) -> Bool {\n    widget == Widget.busy\n}\n"
    }

    private static let countSites = ["Sources/App/Gadget.swift:2", "Sources/App/Gadget.swift:3", "Sources/App/Gadget.swift:8"]

    /// A stored property read and written at three lines: `references to` counts them as the reads and writes above and lists none of them again.
    @Test
    func aPropertysReferencesAreCountedAgainstItsReadsAndWrites() async throws {
        let answer = try await Self.refs("Gizmo.count", in: Self.package())
        let above = Self.siteLines(in: answer, under: "reads and writes of App.Gizmo.count")

        #expect(above.sorted() == Self.countSites)
        #expect(Self.siteLines(in: answer, under: "references to App.Gizmo.count").isEmpty)
        #expect(answer.contains("references to App.Gizmo.count (3 in 1 file, 3 of them the reads and writes above):"))
    }

    /// An enum case's uses are the section above its references.
    @Test
    func anEnumCasesReferencesAreCountedAgainstItsUses() async throws {
        let answer = try await Self.refs("Widget.busy", in: Self.package())

        #expect(!Self.siteLines(in: answer, under: "uses of App.Widget.busy").isEmpty)
        #expect(Self.siteLines(in: answer, under: "references to App.Widget.busy").isEmpty)
        #expect(answer.contains(" of them the uses above):"))
    }

    /// A function's heading is unchanged.
    @Test
    func aFunctionsHeadingStillNamesTheCallSites() async throws {
        let answer = try await Self.refs("Gizmo.ping", in: Self.package())

        #expect(answer.contains("references to App.Gizmo.ping() (1 in 1 file, 1 of them the call sites above):"))
    }

    /// The folded lines are still on the reads and writes rows, so the lines the answer locates and shows are every site, none lost to the fold.
    @Test
    func theFoldLosesNoLocatedLine() async throws {
        let answer = try await Self.refs("Gizmo.count", in: Self.package())
        let expected = Set(Self.countSites.map { site -> ExactAnswer.Location in
            let parts = site.components(separatedBy: ":")
            return ExactAnswer.Location(path: parts[0], line: Int(parts[1]) ?? 0)
        })

        #expect(ExactAnswer.locations(inWhereAnswer: answer).isSuperset(of: expected))
        #expect(ExactAnswer.shownLocations(inWhereAnswer: answer).isSuperset(of: expected))
    }

    private static func package() throws -> URL {
        let root = try MCPTestRepo.make(declaring: "Alpha")
        try MCPTestRepo.add([
            "Package.swift": "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])\n",
            "Sources/App/Gizmo.swift": gizmo,
            "Sources/App/Gadget.swift": gadget,
        ], to: root)
        try MCPTestRepo.build(root)
        return root
    }

    /// `where <symbol> --refs`, asked again until the store has finished loading, failing after two minutes rather than asserting on a warming answer.
    private static func refs(_ symbol: String, in root: URL) async throws -> String {
        let engine = try SiftEngine(directory: root)
        let giveUp = Date().addingTimeInterval(120)
        while true {
            let freshness = try await engine.ensureFresh()
            let answer = try await engine.lookup(symbol: symbol, freshness: freshness, options: WhereOptions(includeReferences: true))
            if !answer.contains("semantic: " + SemanticAxis.warming.rendered) {
                return answer
            }
            struct StillWarming: Error {}
            guard Date() < giveUp else { throw StillWarming() }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Every `path:line` the section headed by `heading` lists, from a file heading with `:line` rows under it or `path (N): line, line`.
    private static func siteLines(in answer: String, under heading: String) -> [String] {
        var sites: [String] = []
        var inSection = false
        var file: String?
        for line in answer.components(separatedBy: "\n") {
            if !line.hasPrefix(" ") {
                inSection = line.hasPrefix(heading)
                file = nil
                continue
            }
            guard inSection else { continue }
            if let row = line.firstMatch(of: #/^ {4}:(\d+)/#), let file {
                sites.append("\(file):\(row.1)")
            } else if let header = line.firstMatch(of: #/^ {2}(\S+\.swift) \(\d+\):(.*)$/#) {
                file = String(header.1)
                let listed = header.2.prefix { $0 == " " || $0 == "," || $0.isNumber }
                sites += listed.split(separator: ",").map { "\(header.1):\($0.trimmingCharacters(in: .whitespaces))" }
            }
        }
        return sites
    }
}
