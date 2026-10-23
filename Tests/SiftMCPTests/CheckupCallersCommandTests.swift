//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure checkup`'s `callers` check over real changes in a temporary repository.
@Suite(.temporaryDirectories)
struct CheckupCallersCommandTests {
    private static func gizmo(spin: String? = "    func spin(speed: Int) {}\n") -> String {
        "struct Gizmo {\n\(spin ?? "")    func halt() {}\n}\n"
    }

    private static var rig: String {
        "struct Rig {\n    func first() {\n        Gizmo().spin(speed: 1)\n    }\n    func second() {\n        Gizmo().spin(speed: 2)\n    }\n}\n"
    }

    private static func repository(extra: [String: String] = [:]) throws -> URL {
        let root = try MCPTestRepo.make()
        let files = ["Sources/App/Gizmo.swift": gizmo(), "Sources/App/Rig.swift": rig]
        try MCPTestRepo.add(files.merging(extra) { $1 }, to: root)
        return root
    }

    private static func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func answer(in repository: URL, range: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String] {
        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let (text, refused) = try await CheckupCommand.parse(["--root", repository.path] + (range.map { [$0] } ?? [])).answer(registry: registry)
        #expect(!refused, sourceLocation: sourceLocation)
        return text.split(separator: "\n").map(String.init)
    }

    private static func callers(_ lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix("callers ") }
    }

    private static func checked(_ lines: [String]) -> String {
        lines.first { $0.hasPrefix("checked: ") } ?? ""
    }

    @Test
    func aRemovedMemberCountsOnlyTheCallerOnALineTheChangeDidNotEdit() async throws {
        let root = try Self.repository()
        try Self.write(Self.gizmo(spin: nil), "Sources/App/Gizmo.swift", in: root)
        try Self.write(Self.rig.replacingOccurrences(of: "spin(speed: 1)", with: "spin(speed: 9)"), "Sources/App/Rig.swift", in: root)

        let found = try await Self.callers(Self.answer(in: root))

        #expect(found.count == 1)
        #expect(found.first?.contains("Sources/App/Gizmo.swift:2") == true)
        #expect(found.first?.contains("Gizmo.spin(speed:) removed; 1 caller on lines this change did not edit, first Sources/App/Rig.swift:6 (name-matched)") == true)
        #expect(found.first?.hasSuffix("swift-sure diff") == true)
    }

    /// Pins that a callers finding points to `diff` over the range the checkup was given, bare where none was.
    @Test
    func theCallersPointerCarriesTheRangeTheCheckupWasGiven() async throws {
        let root = try Self.repository()
        try MCPTestRepo.run(git: ["tag", "base"], in: root)
        try Self.write(Self.gizmo(spin: "    func spin(speed: Double) {}\n"), "Sources/App/Gizmo.swift", in: root)
        try MCPTestRepo.run(git: ["add", "-A"], in: root)
        try MCPTestRepo.run(git: ["commit", "-m", "edit"], in: root)

        let ranged = try await Self.callers(Self.answer(in: root, range: "base..HEAD"))

        #expect(ranged.count == 1)
        #expect(ranged.first?.hasSuffix(" — swift-sure diff base..HEAD") == true)

        try Self.write(Self.gizmo(spin: "    func spin(speed: Float) {}\n"), "Sources/App/Gizmo.swift", in: root)

        let bare = try await Self.callers(Self.answer(in: root))

        #expect(bare.first?.hasSuffix(" — swift-sure diff") == true)
    }

    @Test
    func aSignatureChangeWithCallersIsAFinding() async throws {
        let root = try Self.repository()
        try Self.write(Self.gizmo(spin: "    func spin(speed: Double) {}\n"), "Sources/App/Gizmo.swift", in: root)

        let lines = try await Self.answer(in: root)
        let found = Self.callers(lines)

        #expect(found.count == 1)
        #expect(found.first?.contains("signature changed; 2 callers on lines this change did not edit, first Sources/App/Rig.swift:3") == true)
        #expect(Self.checked(lines).contains("callers ("))
    }

    @Test
    func aNarrowedMemberIsAFindingAndAWidenedOneIsNoSubject() async throws {
        let narrowed = try Self.repository()
        try Self.write(Self.gizmo(spin: "    private func spin(speed: Int) {}\n"), "Sources/App/Gizmo.swift", in: narrowed)
        let widened = try Self.repository()
        try Self.write(Self.gizmo(spin: "    public func spin(speed: Int) {}\n"), "Sources/App/Gizmo.swift", in: widened)

        let narrowedLines = try await Self.callers(Self.answer(in: narrowed))
        let widenedAnswer = try await Self.answer(in: widened)

        #expect(narrowedLines.first?.contains("narrowed; 2 callers") == true)
        #expect(Self.callers(widenedAnswer).isEmpty)
        #expect(Self.checked(widenedAnswer).contains("callers"))
    }

    @Test
    func aCallerMovedByUncommittedLinesIsStillMatchedToTheLineTheRangeEdited() async throws {
        let root = try Self.repository()
        try MCPTestRepo.run(git: ["checkout", "-b", "feat"], in: root)
        try MCPTestRepo.add([
            "Sources/App/Gizmo.swift": Self.gizmo(spin: nil),
            "Sources/App/Rig.swift": Self.rig.replacingOccurrences(of: "spin(speed: 1)", with: "spin(speed: 9)"),
        ], to: root)
        try Self.write("// one\n// two\n// three\n" + Self.rig.replacingOccurrences(of: "spin(speed: 1)", with: "spin(speed: 9)"), "Sources/App/Rig.swift", in: root)

        let found = try await Self.callers(Self.answer(in: root, range: "main...HEAD"))

        #expect(found.count == 1)
        #expect(found.first?.contains("removed; 1 caller on lines this change did not edit, first Sources/App/Rig.swift:9") == true)
    }

    @Test
    func aBoundThatStopsTheLookupPartWayCountsWhatItLeftOut() async throws {
        let names = (1 ... 25).map { "f\($0)" }
        let members = names.map { "    func \($0)() {}\n" }.joined()
        let uses = names.map { "        Chute().\($0)()\n" }.joined()
        let root = try Self.repository(extra: [
            "Sources/App/Chute.swift": "struct Chute {\n\(members)}\n",
            "Sources/App/Slide.swift": "struct Slide {\n    func run() {\n\(uses)    }\n}\n",
        ])
        try Self.write("struct Chute {}\n", "Sources/App/Chute.swift", in: root)

        let lines = try await Self.answer(in: root)

        #expect(Self.callers(lines).count == 20)
        #expect(Self.checked(lines).contains("20 of 25 members; 5 not looked up"))
    }

    @Test
    func aBoundSkipsTheMembersLastInTheFileNotThoseLastByName() async throws {
        let names = (1 ... 23).map { "knob\($0)" }
        let members = names.map { "    func \($0)() {}\n" }.joined()
        let uses = names.map { "        Chute().\($0)()\n" }.joined()
        let root = try Self.repository(extra: [
            "Sources/App/Chute.swift": "struct Chute {\n\(members)}\n",
            "Sources/App/Slide.swift": "struct Slide {\n    func run() {\n\(uses)    }\n}\n",
        ])
        try Self.write("struct Chute {}\n", "Sources/App/Chute.swift", in: root)

        let lines = try await Self.answer(in: root)
        let found = Self.callers(lines)

        #expect(found.count == 20)
        #expect(found.contains { $0.contains("Chute.knob20() removed") })
        #expect(found.contains { $0.contains("Chute.knob2() removed") })
        for skipped in ["knob21", "knob22", "knob23"] {
            #expect(!found.contains { $0.contains("Chute.\(skipped)() removed") })
        }
        #expect(Self.checked(lines).contains("20 of 23 members; 3 not looked up"))
    }

    @Test
    func aRangeWithNoSubjectIsCheckedWithNothingFound() async throws {
        let root = try Self.repository()
        try Self.write("// a note\n", "Sources/App/Note.swift", in: root)

        let lines = try await Self.answer(in: root)

        #expect(Self.callers(lines).isEmpty)
        #expect(Self.checked(lines).contains("callers"))
    }

    @Test
    func aCallersFindingIsListedBeforeADuplicateFinding() async throws {
        let calls = ["loadAlpha", "loadBeta", "loadGamma", "loadDelta", "loadEpsilon", "loadZeta"]
        let packs = ["packOne", "packTwo", "packThree", "packFour", "packFive", "packSix"]
        func body(_ names: [String]) -> String {
            names.map { "        \($0)()\n" }.joined()
        }
        let root = try Self.repository(extra: [
            "Sources/App/Widget.swift": "struct Widget {\n    func wobble() {\n\(body(calls))    }\n}\n",
            "Sources/App/Gizmo.swift": "struct Gizmo {\n    func wobble() {\n\(body(packs))    }\n    func spin(speed: Int) {}\n}\n",
        ])
        try Self.write("struct Gizmo {\n    func wobble() {\n\(body(calls))    }\n}\n", "Sources/App/Gizmo.swift", in: root)

        let lines = try await Self.answer(in: root)
        let callersAt = lines.firstIndex { $0.hasPrefix("callers ") }
        let duplicateAt = lines.firstIndex { $0.hasPrefix("duplicate ") }

        #expect(callersAt != nil)
        #expect(duplicateAt != nil)
        #expect((callersAt ?? 0) < (duplicateAt ?? 0))
    }
}
