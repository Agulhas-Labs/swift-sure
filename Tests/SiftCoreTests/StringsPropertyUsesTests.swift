//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A literal held in a property lists that property's uses, by written name, under its source-literal row.
@Suite(.temporaryDirectories)
struct StringsPropertyUsesTests {
    private static func makeRepo(files: [String: String]) throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        for (path, contents) in files {
            try TestSources.write(contents, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "property fixture")
        return try SiftEngine(directory: root)
    }

    private static var holder: String {
        """
        struct Gizmo {
            static let missing = "Gizmo went missing"
            func show() {
                present(Self.missing)
            }
        }
        """
    }

    @Test
    func aPropertyHoldingTheLiteralListsItsUseUnderTheRow() throws {
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": Self.holder, "Sources/Gizmo/Other.swift": "func other() { _ = Gizmo.missing }"])

        let output = try engine.strings(query: "Gizmo went missing")

        #expect(output.contains("  Gizmo.missing — Sources/Gizmo/Gizmo.swift:2: \"Gizmo went missing\"\n      Sources/Gizmo/Gizmo.swift:4 in Gizmo.show(): present(Self.missing)"))
        #expect(output.contains("      Sources/Gizmo/Other.swift:1 in other(): func other() { _ = Gizmo.missing }"))
        #expect(!output.contains("Gizmo.swift:2 in"))
    }

    @Test
    func aPrivatePropertyIsLookedForInItsDeclaringFileOnly() throws {
        let source = """
        struct Gizmo {
            private static let hidden = "Gizmo hid"
            func show() { present(Self.hidden) }
        }
        """
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": source, "Sources/Gizmo/Other.swift": "struct Widget { func go() { present(hidden) } }"])

        let output = try engine.strings(query: "Gizmo hid")

        #expect(output.contains("Sources/Gizmo/Gizmo.swift:3 in Gizmo.show()"))
        #expect(!output.contains("Other.swift"))
    }

    @Test
    func aPropertyWithNoUseSaysItIsWrittenNowhere() throws {
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": "struct Gizmo {\n    static let idle = \"Gizmo sat idle\"\n}"])

        let output = try engine.strings(query: "Gizmo sat idle")

        #expect(output.contains("Gizmo.idle — Sources/Gizmo/Gizmo.swift:2: \"Gizmo sat idle\"\n      written nowhere outside its declaration"))
    }

    @Test
    func aComputedPropertyReturningTheLiteralListsItsUses() throws {
        let source = """
        struct Gizmo {
            var title: String {
                "Gizmo title text"
            }
            func show() { present(title) }
        }
        """
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": source])

        let output = try engine.strings(query: "Gizmo title text")

        #expect(output.contains("      Sources/Gizmo/Gizmo.swift:5 in Gizmo.show(): func show() { present(title) }"))
    }

    @Test
    func aLiteralInAFunctionBodyListsNoSites() throws {
        let source = """
        struct Gizmo {
            func show() { present("Gizmo in a body") }
        }
        """
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": source])

        let output = try engine.strings(query: "Gizmo in a body")

        #expect(output.contains("Gizmo.show() — Sources/Gizmo/Gizmo.swift:2"))
        #expect(!output.contains("written nowhere"))
        #expect(!output.contains("      Sources/"))
    }

    @Test
    func onlyTheFirstFivePropertyHeldRowsGetSites() throws {
        let lines = (1 ... 7).map { "    static let message\($0) = \"Gizmo many \($0)\"" }
        let source = "struct Gizmo {\n" + lines.joined(separator: "\n") + "\n}"
        let engine = try Self.makeRepo(files: ["Sources/Gizmo/Gizmo.swift": source])

        let output = try engine.strings(query: "Gizmo many")

        #expect(output.components(separatedBy: "written nowhere outside its declaration").count - 1 == 5)
    }
}
