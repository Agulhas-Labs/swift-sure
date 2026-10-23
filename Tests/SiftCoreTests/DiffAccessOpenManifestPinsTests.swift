//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A manifest that is not the whole story of the build (a `.dependencies` list changed after the `Package(...)` call, or a version-specific manifest beside it) rules no module out for an implicit-member `init(` call.
@Suite(.temporaryDirectories)
struct DiffAccessOpenManifestPinsTests {
    private static let implicitInit = DiffAccessReachInitPinsTests.implicitInit
    private static let facadeCaller = "import GizmoCore\n\nfunc refill(_ holder: inout Holder4) {\n    holder.crate = \(implicitInit)\n}\n"
    private static let kitCaller = "import GizmoKit\n\nfunc refill(_ holder: inout Holder4) {\n    holder.crate = \(implicitInit)\n}\n"
    private static let expected = "  + GizmoKit.Crate4\(implicitInit)  Sources/GizmoKit/Added.swift:2  public → package: used only from GizmoTools, in this package"

    /// A dependency appended to a target after the `Package(...)` call makes the manifest open, so the caller that reaches `GizmoKit` through the re-export keeps `package`.
    @Test func aDependencyAppendedAfterThePackageCallOpensTheManifest() async throws {
        let answer = try await Self.diff(manifest: """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [
                .target(name: "GizmoKit"),
                .target(name: "GizmoCore"),
                .target(name: "GizmoTools", dependencies: ["GizmoCore"]),
            ]
        )

        for target in package.targets where target.name == "GizmoCore" {
            target.dependencies.append("GizmoKit")
        }
        """)

        #expect(answer.contains(Self.expected), "\(answer)")
    }

    /// A `Package@swift-*.swift` beside `Package.swift` makes the manifest open, so the dependencies only that file states are not ruled out.
    @Test func aVersionSpecificManifestBesideItOpensTheManifest() async throws {
        let answer = try await Self.diff(manifest: Self.bareManifest(toolsVersion: "5.9"), versioned: """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [
                .target(name: "GizmoKit"),
                .target(name: "GizmoCore", dependencies: ["GizmoKit"]),
                .target(name: "GizmoTools", dependencies: ["GizmoCore"]),
            ]
        )
        """)

        #expect(answer.contains(Self.expected), "\(answer)")
    }

    /// The first reviewed input: kit and tools declared bare, a dependency appended in a loop, and the caller importing the kit directly.
    @Test func anAppendedDependencyWithADirectImportKeepsPackage() async throws {
        let answer = try await Self.diff(manifest: """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [.target(name: "GizmoKit"), .target(name: "GizmoTools")]
        )

        for target in package.targets where target.name != "GizmoKit" {
            target.dependencies.append("GizmoKit")
        }
        """, caller: Self.kitCaller)

        #expect(answer.contains(Self.expected), "\(answer)")
    }

    /// The second reviewed input: a tools 5.9 manifest with no dependency, a 6.0 one beside it adding it, and the caller importing the kit directly.
    @Test func aVersionSpecificManifestWithADirectImportKeepsPackage() async throws {
        let answer = try await Self.diff(manifest: Self.bareManifest(toolsVersion: "5.9"), versioned: """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [.target(name: "GizmoKit"), .target(name: "GizmoTools", dependencies: ["GizmoKit"])]
        )
        """, caller: Self.kitCaller)

        #expect(answer.contains(Self.expected), "\(answer)")
    }

    /// A manifest that only labels `dependencies:` arguments stays closed: a caller that cannot reach the kit and does not import it leaves `internal`.
    @Test func aLabelledDependenciesArgumentLeavesTheManifestClosed() async throws {
        let answer = try await Self.diff(manifest: Self.bareManifest(toolsVersion: "6.0"), caller: "func stamp(_ holder: inout Holder4) {\n    holder.crate = \(Self.implicitInit)\n}\n")

        #expect(answer.contains("public → internal: no use by that name outside module GizmoKit"), "\(answer)")
    }
}

extension DiffAccessOpenManifestPinsTests {
    /// A manifest declaring `GizmoKit`, `GizmoCore` and `GizmoTools` with no dependency between them.
    static func bareManifest(toolsVersion: String) -> String {
        """
        // swift-tools-version: \(toolsVersion)
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [
                .target(name: "GizmoKit", dependencies: []),
                .target(name: "GizmoCore"),
                .target(name: "GizmoTools"),
            ]
        )
        """
    }

    /// The diff of a working tree that adds `crate` to `GizmoKit` and `caller` to `GizmoTools`, over a repository with `manifest` (and `versioned` as `Package@swift-6.0.swift`) and a `GizmoCore` that re-exports `GizmoKit`.
    static func diff(manifest: String, versioned: String? = nil, caller: String = facadeCaller) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(manifest, to: "Package.swift", in: root)
        if let versioned {
            try TestSources.write(versioned, to: "Package@swift-6.0.swift", in: root)
        }
        try TestSources.write("@_exported import GizmoKit\n", to: "Sources/GizmoCore/Facade.swift", in: root)
        for target in ["GizmoKit", "GizmoTools"] {
            try TestSources.write("func run() {}\n", to: "Sources/\(target)/Tool.swift", in: root)
        }
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write(DiffAccessReachInitPinsTests.crate, to: "Sources/GizmoKit/Added.swift", in: root)
        try TestSources.write(caller, to: "Sources/GizmoTools/Later.swift", in: root)
        return try await DiffEngineTests.diff(root)
    }
}
