//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the manifest's `exclude:` read and the resolver leaving those paths unclaimed.
@Suite(.temporaryDirectories)
struct SwiftPMManifestExcludeTests {
    /// A target's literal `exclude:` entries are read, a computed element is skipped, and no `exclude:` reads as none.
    @Test
    func literalExcludeEntriesAreRead() {
        let manifest = SwiftPMManifest.parse(source: """
        // swift-tools-version: 6.0
        import PackageDescription

        let skipped = "Skipped.swift"
        let package = Package(
            name: "Multi",
            targets: [
                .target(name: "Lib", exclude: ["Gizmo.swift", skipped, "Old/Dir"]),
                .target(name: "App", path: "Apps/App", exclude: ["Notes"]),
                .target(name: "Plain"),
            ]
        )
        """)

        #expect(manifest.targets.map(\.excludes) == [["Gizmo.swift", "Old/Dir"], ["Notes"], []])
    }

    private static func makeResolver(exclude: String, path: String? = nil, directory: String = "Sources/Lib") throws -> ModuleResolver {
        let root = try TemporaryDirectory.make("exclude").appendingPathComponent("exclude")
        let pathArgument = path.map { ", path: \"\($0)\"" } ?? ""
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(name: "Multi", targets: [.target(name: "Lib"\(pathArgument), exclude: [\(exclude)])])
            """,
            to: "Package.swift",
            in: root
        )
        try TestSources.write("struct A {}\n", to: directory + "/Gizmo.swift", in: root)
        try TestSources.write("struct B {}\n", to: directory + "/Keep.swift", in: root)
        try TestSources.write("struct C {}\n", to: directory + "/Old/Deep.swift", in: root)
        return ModuleResolver(repoRoot: root, config: SiftConfig())
    }

    /// An excluded file claims no module while its siblings stay the target's, for a convention target.
    @Test
    func anExcludedFileUnderAConventionTargetIsUnclaimed() throws {
        let resolver = try Self.makeResolver(exclude: "\"Gizmo.swift\"")

        #expect(resolver.resolvedModule(for: "Sources/Lib/Gizmo.swift") == nil)
        #expect(resolver.resolvedModule(for: "Sources/Lib/Keep.swift") == "Lib")
        #expect(resolver.resolvedModule(for: "Sources/Lib/Old/Deep.swift") == "Lib")
    }

    /// An excluded directory covers the files under it.
    @Test
    func anExcludedDirectoryCoversItsFiles() throws {
        let resolver = try Self.makeResolver(exclude: "\"Old\"")

        #expect(resolver.resolvedModule(for: "Sources/Lib/Old/Deep.swift") == nil)
        #expect(resolver.resolvedModule(for: "Sources/Lib/Keep.swift") == "Lib")
    }

    /// A target with an explicit `path:` leaves out its excludes relative to that path.
    @Test
    func anExcludeUnderAnExplicitPathIsUnclaimed() throws {
        let resolver = try Self.makeResolver(exclude: "\"Gizmo.swift\"", path: "Code/Lib", directory: "Code/Lib")

        #expect(resolver.resolvedModule(for: "Code/Lib/Gizmo.swift") == nil)
        #expect(resolver.resolvedModule(for: "Code/Lib/Keep.swift") == "Lib")
    }
}
