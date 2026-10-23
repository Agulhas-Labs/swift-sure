//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers an `exclude:` rule taking a path back only from the target entry that wrote it, and the rule's path spelling.
@Suite(.temporaryDirectories)
struct SwiftPMExcludeOwnerTests {
    private static func makeRepo(exclude: String, platformSpec: Bool) throws -> URL {
        let root = try TemporaryDirectory.make("owner").appendingPathComponent("owner")
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(name: "Multi", targets: [.target(name: "Lib", exclude: [\(exclude)])])
            """,
            to: "Package.swift",
            in: root
        )
        if platformSpec {
            try TestSources.write(
                """
                name: App
                targets:
                  App:
                    type: application
                    sources: Sources/Lib/Platform
                """,
                to: "project.yml",
                in: root
            )
        }
        try TestSources.write("struct A {}\n", to: "Sources/Lib/Platform/Gizmo.swift", in: root)
        try TestSources.write("struct B {}\n", to: "Sources/Lib/Keep.swift", in: root)
        try TestSources.write("struct C {}\n", to: "Sources/Lib/Fixtures/f.swift", in: root)
        return root
    }

    /// An XcodeGen target claiming the directory outright keeps a file another target's `exclude:` names.
    @Test
    func anExcludeDoesNotTakeAFileBackFromAnXcodeGenClaim() throws {
        let root = try Self.makeRepo(exclude: "\"Platform/Gizmo.swift\"", platformSpec: true)
        let resolver = ModuleResolver(repoRoot: root, config: SiftConfig())

        #expect(resolver.resolvedModule(for: "Sources/Lib/Platform/Gizmo.swift") == "App")
        #expect(resolver.resolvedModule(for: "Sources/Lib/Keep.swift") == "Lib")
    }

    /// A `moduleMap` entry for the directory outranks the manifest's `exclude:` rule.
    @Test
    func anExcludeDoesNotTakeAFileBackFromAConfigMapEntry() throws {
        let root = try Self.makeRepo(exclude: "\"Platform/Gizmo.swift\"", platformSpec: false)
        var config = SiftConfig()
        config.moduleMap = ["Sources/Lib/Platform": "App"]
        let resolver = ModuleResolver(repoRoot: root, config: config)

        #expect(resolver.resolvedModule(for: "Sources/Lib/Platform/Gizmo.swift") == "App")
    }

    /// A `.` or empty component anywhere in an exclude path is dropped before it is joined, so `./Fixtures`, `Platform/./Gizmo.swift` and `Platform//Gizmo.swift` unclaim what they name.
    @Test
    func dotAndEmptyComponentsInAnExcludePathAreDropped() throws {
        let root = try Self.makeRepo(exclude: "\"./Fixtures\", \"Platform/./Gizmo.swift\"", platformSpec: false)
        let resolver = ModuleResolver(repoRoot: root, config: SiftConfig())
        let doubled = try ModuleResolver(
            repoRoot: Self.makeRepo(exclude: "\"Platform//Gizmo.swift\"", platformSpec: false),
            config: SiftConfig()
        )

        #expect(resolver.resolvedModule(for: "Sources/Lib/Fixtures/f.swift") == nil)
        #expect(resolver.resolvedModule(for: "Sources/Lib/Platform/Gizmo.swift") == nil)
        #expect(doubled.resolvedModule(for: "Sources/Lib/Platform/Gizmo.swift") == nil)
        #expect(resolver.resolvedModule(for: "Sources/Lib/Keep.swift") == "Lib")
    }

    /// A `moduleMap` rename at the target's own prefix keeps the target's `exclude:` rule, so the excluded file stays unclaimed while a sibling takes the new name.
    @Test
    func aSamePrefixRenameKeepsASwiftPMTargetsExcludes() throws {
        let root = try Self.makeRepo(exclude: "\"Gizmo.swift\"", platformSpec: false)
        try TestSources.write("struct D {}\n", to: "Sources/Lib/Gizmo.swift", in: root)
        var config = SiftConfig()
        config.moduleMap = ["Sources/Lib": "Depot"]
        let resolver = ModuleResolver(repoRoot: root, config: config)

        #expect(resolver.resolvedModule(for: "Sources/Lib/Gizmo.swift") == nil)
        #expect(resolver.resolvedModule(for: "Sources/Lib/Keep.swift") == "Depot")
    }

    /// A `moduleMap` rename at an XcodeGen target's own prefix keeps the source entry's `excludes:`.
    @Test
    func aSamePrefixRenameKeepsAnXcodeGenTargetsExcludes() throws {
        let root = try TemporaryDirectory.make("owner").appendingPathComponent("owner")
        try TestSources.write(
            """
            name: Gizmo
            targets:
              App:
                type: application
                settings:
                  base:
                    PRODUCT_MODULE_NAME: $(MYSTERY_NAME)
                sources:
                  - path: Sources/App
                    excludes: ["Mac"]
            """,
            to: "project.yml",
            in: root
        )
        try TestSources.write("struct W {}\n", to: "Sources/App/Mac/Widget.swift", in: root)
        try TestSources.write("struct K {}\n", to: "Sources/App/Keep.swift", in: root)
        var config = SiftConfig()
        config.moduleMap = ["Sources/App": "Orchard"]
        let resolver = ModuleResolver(repoRoot: root, config: config)

        #expect(resolver.resolvedModule(for: "Sources/App/Mac/Widget.swift") == nil)
        #expect(resolver.resolvedModule(for: "Sources/App/Keep.swift") == "Orchard")
    }
}
