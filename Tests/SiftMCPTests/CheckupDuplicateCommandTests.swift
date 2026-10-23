//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure checkup`'s `duplicate` check over real working-tree changes in a temporary repository.
@Suite(.temporaryDirectories)
struct CheckupDuplicateCommandTests {
    private static func source(_ type: String, calls: [String], attribute: String = "") -> String {
        let lines = calls.map { "        \($0)()" }.joined(separator: "\n")
        return "struct \(type) {\n\(attribute)    func wobble() {\n\(lines)\n    }\n}\n"
    }

    private static var shared: [String] {
        ["loadAlpha", "loadBeta", "loadGamma", "loadDelta", "loadEpsilon", "loadZeta"]
    }

    private static var different: [String] {
        ["packOne", "packTwo", "packThree", "packFour", "packFive", "packSix"]
    }

    private static func answer(in repository: URL, sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String] {
        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let (text, refused) = try await CheckupCommand.parse(["--root", repository.path]).answer(registry: registry)
        #expect(!refused, sourceLocation: sourceLocation)
        return text.split(separator: "\n").map(String.init)
    }

    private static func duplicates(_ lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix("duplicate ") }
    }

    /// A committed repository holding `Widget` and an unrelated `Gizmo`, ready for a working-tree edit.
    private static func repository(widgetAttribute: String = "", extra: [String: String] = [:]) throws -> URL {
        let root = try MCPTestRepo.make()
        let files = ["Sources/App/Widget.swift": source("Widget", calls: shared, attribute: widgetAttribute), "Sources/App/Gizmo.swift": source("Gizmo", calls: different)]
        try MCPTestRepo.add(files.merging(extra) { $1 }, to: root)
        return root
    }

    private static func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func aBodyChangedDeclarationClearingBothGatesIsAFindingWithTheClosestPair() async throws {
        let root = try Self.repository()
        try Self.write(Self.source("Gizmo", calls: Self.shared), "Sources/App/Gizmo.swift", in: root)

        let lines = try await Self.answer(in: root)
        let found = Self.duplicates(lines)

        #expect(found.count == 1)
        #expect(found.first?.contains("Sources/App/Gizmo.swift:2-9") == true)
        #expect(found.first?.contains("Gizmo.wobble() and Widget.wobble() at Sources/App/Widget.swift:2-9 clear both gates (") == true)
        #expect(found.first?.hasSuffix("swift-sure similar Gizmo.wobble") == true)
        #expect(lines.contains { $0.hasPrefix("checked: ") && $0.contains("duplicates") })
    }

    @Test
    func aMemberOfAWhollyAddedTypeWithADuplicateElsewhereIsAFinding() async throws {
        let root = try Self.repository()
        try Self.write(Self.source("Orchard", calls: Self.shared), "Sources/App/Orchard.swift", in: root)

        let found = try await Self.duplicates(Self.answer(in: root))

        #expect(found.count == 1)
        #expect(found.first?.contains("Sources/App/Orchard.swift:") == true)
        #expect(found.first?.contains("Orchard.wobble() and Widget.wobble()") == true)
    }

    @Test
    func aTestDeclarationIsNotASeed() async throws {
        let root = try Self.repository()
        try Self.write(Self.source("GizmoTests", calls: Self.shared), "Tests/AppTests/GizmoTests.swift", in: root)

        let lines = try await Self.answer(in: root)

        #expect(Self.duplicates(lines).isEmpty)
        #expect(lines.contains { $0.hasPrefix("checked: ") && $0.contains("duplicates") })
    }

    @Test
    func aDeclarationTheChangeDidNotTouchIsNotASeedEvenWithADuplicate() async throws {
        let root = try Self.repository(extra: ["Sources/App/Depot.swift": Self.source("Depot", calls: Self.shared)])
        try Self.write(Self.source("Gizmo", calls: Self.different + ["packSeven"]), "Sources/App/Gizmo.swift", in: root)

        let lines = try await Self.answer(in: root)

        #expect(Self.duplicates(lines).isEmpty)
        #expect(lines.contains { $0.hasPrefix("checked: ") && $0.contains("duplicates") })
    }

    @Test
    func anAttributedDeclarationOnItsOwnLineIsStillSeeded() async throws {
        let root = try Self.repository(widgetAttribute: "    @MainActor\n")
        try Self.write(Self.source("Gizmo", calls: Self.shared, attribute: "    @MainActor\n"), "Sources/App/Gizmo.swift", in: root)

        let found = try await Self.duplicates(Self.answer(in: root))

        #expect(found.count == 1)
        #expect(found.first?.contains("Gizmo.wobble() and Widget.wobble()") == true)
    }

    @Test
    func aRangeChangingNoDeclarationIsNotCheckedWithTheReason() async throws {
        let root = try Self.repository()
        try Self.write("// a note\n", "Sources/App/Note.swift", in: root)

        let lines = try await Self.answer(in: root)

        #expect(lines.contains { $0.contains("not checked: ") && $0.contains("duplicates (no added or body-changed declaration)") })
    }
}
