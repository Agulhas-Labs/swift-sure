//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with a fresh index store counts an implicit-member `init(` call in a file of another module the store does not cover as a use of every initializer of each module that file's module can reach, imported there or not.
@Suite(.temporaryDirectories, .serialized)
struct DiffAccessStoreReachInitPinsTests {
    /// A built package whose last commit adds `Crate4` to `GizmoKit`, with a file in `GizmoTools` reaching it through a re-export and one in `GizmoApp` through a returned value, both added after the build.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "diff-access-store-reach-implicit-init") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [
                        .target(name: "GizmoKit"),
                        .target(name: "GizmoCore", dependencies: ["GizmoKit"]),
                        .target(name: "GizmoExtras", dependencies: ["GizmoKit"]),
                        .target(name: "GizmoTools", dependencies: ["GizmoCore"]),
                        .target(name: "GizmoApp", dependencies: ["GizmoExtras"]),
                    ]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.write("@_exported import GizmoKit\n", to: "Sources/GizmoCore/Facade.swift", in: root)
            try TestSources.write("import GizmoKit\n\npublic func relayHolder() -> Holder4 {\n    Holder4()\n}\n", to: "Sources/GizmoExtras/Relay.swift", in: root)
            try TestSources.write("func run() {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.write("func run() {}\n", to: "Sources/GizmoApp/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write(DiffAccessReachInitPinsTests.crate, to: "Sources/GizmoKit/Crate.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root)
            let implicit = DiffAccessReachInitPinsTests.implicitInit
            try TestSources.write("import GizmoCore\n\nfunc refill(_ holder: inout Holder4) {\n    holder.crate = \(implicit)\n}\n", to: "Sources/GizmoTools/Later.swift", in: root)
            try TestSources.write("import GizmoExtras\n\nfunc refill() {\n    var held = relayHolder()\n    held.crate = \(implicit)\n}\n", to: "Sources/GizmoApp/Later.swift", in: root)
        }
    }

    /// The last commit's diff, read by the fixture's engine.
    private static func diffOfTheWorkingTree() async throws -> String {
        let fixture = try await fixture()
        return try await fixture.withEngine { engine in
            let range = try DiffRange.resolve("HEAD", git: GitContext(repoRoot: fixture.root))
            return try await engine.diff(options: DiffOptions(range: range), freshness: engine.ensureFresh())
        }
    }

    /// Narrowing the initializer of `Crate4` to `internal` fails for both files: one reaches the type through a re-export, the other through a value `GizmoExtras` returns, and neither imports `GizmoKit`.
    @Test func anImplicitInitializerInAnUncoveredFileThatReachesTheModuleWithoutImportingItAllowsPackage() async throws {
        let answer = try await Self.diffOfTheWorkingTree()

        #expect(answer.contains("  + GizmoKit.Crate4\(DiffAccessReachInitPinsTests.implicitInit)  Sources/GizmoKit/Crate.swift:2  public → package: used only from GizmoApp, GizmoTools, in this package"), "\(answer)")
    }
}
