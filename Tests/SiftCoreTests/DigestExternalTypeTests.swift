//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `digest Dep.member` and `digest Dep` for a `Dep` the repository writes and declares nowhere: the answer says the type is declared outside the repository and the member is neither confirmed nor ruled out, never that the path is mistyped.
@Suite(.temporaryDirectories)
struct DigestExternalTypeTests {
    /// A package whose one target writes a dependency's `Tally` as a parameter's type and reads its `count`.
    private static let files = [
        "Package.swift": "// swift-tools-version:5.9\nimport PackageDescription\n\nlet package = Package(name: \"Gizmo\", targets: [.target(name: \"GizmoCore\")])\n",
        "Sources/GizmoCore/Total.swift": "import Dep\n\nfunc total(_ tally: Tally) -> Int {\n    tally.count\n}\n",
    ]

    /// A repository type declaring a `count` of its own.
    private static let box = ["Sources/GizmoCore/Box.swift": "struct Box {\n    var count: Int { 1 }\n}\n"]

    /// The repository's extension of `Tally`, declaring `doubled` and no `count`.
    private static let tallyExtension = ["Sources/GizmoCore/Tally+Doubled.swift": "import Dep\n\nextension Tally {\n    var doubled: Int { 2 }\n}\n"]

    private static var headline: String {
        "Tally — declared outside this repo (or not indexed), so count is neither confirmed nor ruled out on it"
    }

    /// The answer `digest` gives for `target` over the fixture and `extraFiles`.
    private static func answer(_ target: String, extraFiles: [String: String] = [:]) async throws -> MeasuredAnswer {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files.merging(extraFiles, uniquingKeysWith: { $1 }) {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "a dependency's types, unbuilt")
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return try engine.measuredDigest(target: target, options: DigestOptions())
    }

    /// With no extension of the type and no other `count`, the member is neither confirmed nor ruled out, and the answer is a miss by both readings.
    @Test
    func aMemberOfAnUnextendedTypeIsNeitherConfirmedNorRuledOut() async throws {
        let answer = try await Self.answer("Tally.count")

        #expect(answer.text.contains(Self.headline), "\(answer.text)")
        #expect(answer.text.contains("no extension of Tally in this repository"), "\(answer.text)")
        #expect(answer.text.contains("where --refs Tally.count lists this repository's uses of it"), "\(answer.text)")
        #expect(!answer.text.contains("no symbol named count"), "\(answer.text)")
        #expect(answer.missed)
        #expect(DigestMiss.isMiss(inAnswer: answer.text), "\(answer.text)")
    }

    /// The repository's own `count` on another type is listed under a heading that says nothing of `Tally`, never as a mistyped path.
    @Test
    func theRepositorysSameNamedMembersAreListed() async throws {
        let answer = try await Self.answer("Tally.count", extraFiles: Self.box)

        #expect(answer.text.contains(Self.headline), "\(answer.text)")
        #expect(answer.text.contains("other declarations of count in this repository (1):\n  GizmoCore.Box.count — var — Sources/GizmoCore/Box.swift:2"), "\(answer.text)")
        #expect(!answer.text.contains("could not resolve the path"), "\(answer.text)")
        #expect(!answer.text.contains("is declared, but not under"), "\(answer.text)")
    }

    /// A member the repository's extension of the type declares is served as any member is.
    @Test
    func aMemberAnExtensionDeclaresIsServed() async throws {
        let answer = try await Self.answer("Tally.doubled", extraFiles: Self.tallyExtension)

        #expect(answer.text.contains("var doubled: Int { 2 }"), "\(answer.text)")
        #expect(!answer.text.contains("declared outside this repo"), "\(answer.text)")
        #expect(!answer.missed)
    }

    /// An extension that does not declare the member is listed by its header line, with the digest that serves its members and the query for the member's uses.
    @Test
    func anExtensionWithoutTheMemberIsListed() async throws {
        let answer = try await Self.answer("Tally.count", extraFiles: Self.tallyExtension)

        #expect(answer.text.contains(Self.headline), "\(answer.text)")
        #expect(answer.text.contains("extensions of Tally (1) — digest Tally serves their members:\n  extension Tally — GizmoCore — Sources/GizmoCore/Tally+Doubled.swift:3-5"), "\(answer.text)")
        #expect(answer.text.contains("where --refs Tally.count lists this repository's uses of it"), "\(answer.text)")
        #expect(answer.missed)
    }

    /// A generic parameter written in an extension of the type declaring it is declared there, so a member asked of it keeps the wrong-path answer.
    @Test
    func aGenericParameterKeepsTheWrongPathAnswer() async throws {
        let holder = ["Sources/GizmoCore/Holder.swift": "struct Holder<T> {}\n\nextension Holder {\n    func read(_ value: T) -> T {\n        value\n    }\n}\n"]
        let answer = try await Self.answer("T.count", extraFiles: Self.box.merging(holder) { $1 })

        #expect(answer.text.contains("could not resolve the path T.count — count is declared, but not under T:"), "\(answer.text)")
        #expect(!answer.text.contains("declared outside this repo"), "\(answer.text)")
    }

    /// A longer path asks about its last qualifier, the type.
    @Test
    func aLongerPathAsksAboutItsLastQualifier() async throws {
        let answer = try await Self.answer("Dep.Tally.count")

        #expect(answer.text.contains(Self.headline), "\(answer.text)")
        #expect(answer.missed)
    }

    /// A name a file imports as a module and writes as the qualifier of a following name is that module, so a member asked of it keeps the wrong-path answer.
    @Test
    func anImportedModuleQualifierKeepsTheWrongPathAnswer() async throws {
        let net = [
            "Sources/GizmoCore/Fetch.swift": "import Net\n\nfunc fetch() -> Net.URL? {\n    nil\n}\n",
            "Sources/GizmoCore/Endpoint.swift": "struct Endpoint {\n    var host: String { \"\" }\n}\n",
        ]
        let answer = try await Self.answer("Net.host", extraFiles: net)

        #expect(answer.text.contains("could not resolve the path Net.host — host is declared, but not under Net:"), "\(answer.text)")
        #expect(!answer.text.contains("declared outside this repo"), "\(answer.text)")
    }

    /// A type the repository neither declares nor writes keeps the wrong-path answer.
    @Test
    func anUnwrittenTypeKeepsTheWrongPathAnswer() async throws {
        let answer = try await Self.answer("Missing.count", extraFiles: Self.box)

        #expect(answer.text.contains("could not resolve the path Missing.count — count is declared, but not under Missing:"), "\(answer.text)")
        #expect(!answer.text.contains("declared outside this repo"), "\(answer.text)")
    }

    /// A file the parser could not finish may hold the type's declaration, so the banner stands above the headline.
    @Test
    func aParseErrorElsewhereCarriesTheBanner() async throws {
        let answer = try await Self.answer("Tally.count", extraFiles: ["Sources/GizmoCore/Broken.swift": "struct Truncated {\n    func swallowedFromHereOn(\n}\n"])
        let lines = answer.text.split(separator: "\n").map(String.init)

        let banner = try #require(lines.firstIndex { $0.hasPrefix("⚠ parse errors elsewhere in this repo") }, "\(answer.text)")
        let claim = try #require(lines.firstIndex(of: Self.headline), "\(answer.text)")

        #expect(banner < claim, "\(answer.text)")
        #expect(answer.text.contains("Sources/GizmoCore/Broken.swift"), "\(answer.text)")
    }

    /// The type asked for itself, extended nowhere, is said to be declared outside the repository with no local extensions, in place of no symbol of the name.
    @Test
    func theUnextendedTypeItselfHasNoLocalExtensions() async throws {
        let answer = try await Self.answer("Tally")

        #expect(answer.text.contains("Tally — declared outside this repo (or not indexed); no local extensions"), "\(answer.text)")
        #expect(!answer.text.contains("no symbol named Tally"), "\(answer.text)")
        #expect(answer.missed)
        #expect(DigestMiss.isMiss(inAnswer: answer.text), "\(answer.text)")
    }

    /// A member declared in the repository's extension of the bare type is served for a longer path ending in the type.
    @Test
    func aLongerPathServesTheBareExtensionsMember() async throws {
        let answer = try await Self.answer("Dep.Tally.doubled", extraFiles: Self.tallyExtension)

        #expect(answer.text.contains("var doubled: Int { 2 }"), "\(answer.text)")
        #expect(!answer.missed)
    }

    /// An extension written under another parent is that parent's type, so its member is never served for this path, nor listed as this type's extension.
    @Test
    func anotherParentsExtensionIsNotThisTypes() async throws {
        let files = [
            "Sources/GizmoCore/Open.swift": "import Depot\n\nfunc open(_ settings: Depot.Settings) -> Int {\n    settings.count\n}\n",
            "Sources/GizmoCore/Orchard+Settings.swift": "import Orchard\n\nextension Orchard.Settings {\n    var timeout: Int { 3 }\n}\n",
        ]
        let member = try await Self.answer("Depot.Settings.timeout", extraFiles: files)
        let listed = try await Self.answer("Depot.Settings.count", extraFiles: files)

        #expect(!member.text.contains("var timeout: Int { 3 }"), "\(member.text)")
        #expect(member.text.contains("Settings — declared outside this repo (or not indexed), so timeout is neither confirmed nor ruled out on it"), "\(member.text)")
        #expect(member.missed)
        #expect(listed.text.contains("no extension of Settings in this repository"), "\(listed.text)")
        #expect(!listed.text.contains("extension Orchard.Settings"), "\(listed.text)")
    }

    /// A bare type name names no parent, so an extension written under any parent is listed as that type's.
    @Test
    func aBareNameCountsAnExtensionUnderAnyParent() async throws {
        let files = [
            "Sources/GizmoCore/Open.swift": "import Depot\n\nfunc open(_ settings: Depot.Settings) -> Int {\n    settings.count\n}\n",
            "Sources/GizmoCore/Orchard+Settings.swift": "import Orchard\n\nextension Orchard.Settings {\n    var timeout: Int { 3 }\n}\n",
        ]
        let listed = try await Self.answer("Settings.count", extraFiles: files)

        #expect(!listed.text.contains("no extension of Settings in this repository"), "\(listed.text)")
        #expect(listed.text.contains("extension Orchard.Settings"), "\(listed.text)")
    }
}
