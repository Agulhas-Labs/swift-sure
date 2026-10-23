//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with a fresh index store keeps an initializer public where an enum case's default value references it, and where a file the store does not cover calls an initializer by implicit member in its module's fragile code.
@Suite(.temporaryDirectories, .serialized)
struct DiffAccessStoreImplicitInitPinsTests {
    /// A built package whose last commit adds initializers called from `GizmoTools`, with a file added to `GizmoKit` after the build.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "diff-access-store-implicit-init") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [
                        .target(name: "GizmoKit"),
                        .target(name: "SproutKit"),
                        .target(name: "GizmoTools", dependencies: ["GizmoKit", "SproutKit"]),
                    ]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.write("struct Bud {}\n", to: "Sources/SproutKit/Bud.swift", in: root)
            try TestSources.write("func run() {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write(Self.sprout, to: "Sources/SproutKit/Sprout.swift", in: root)
            try TestSources.write("public struct Pail {\n    public init() {}\n}\n", to: "Sources/SproutKit/Pail.swift", in: root)
            try TestSources.write(Self.crate, to: "Sources/GizmoKit/Crate.swift", in: root)
            try TestSources.write("import GizmoKit\nimport SproutKit\n\nfunc run() {\n    _ = Seed()\n    _ = Pail()\n    _ = Crate3()\n}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root)
            try TestSources.write(Self.later, to: "Sources/GizmoKit/Later.swift", in: root)
        }
    }

    /// The last commit's diff, read by the fixture's engine.
    private static func diffOfTheLastCommit() async throws -> String {
        let fixture = try await fixture()
        return try await fixture.withEngine { engine in
            let range = try DiffRange.resolve("HEAD", git: GitContext(repoRoot: fixture.root))
            return try await engine.diff(options: DiffOptions(range: range), freshness: engine.ensureFresh())
        }
    }

    /// Narrowing `Seed.init()` to `package` fails with "initializer 'init()' is package and cannot be referenced from a default argument value": the store's reference sits in the enum case's associated value.
    @Test func aReferenceInAnEnumCasesDefaultValueKeepsItsLevel() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("  uses resolved by the index store"), "\(answer)")
        #expect(!answer.contains("SproutKit.Seed.init()"), "\(answer)")
    }

    /// Narrowing the initializer of `Crate3` to `package` fails with "initializer 'init()' is package and cannot be referenced from an '@inlinable' function": the call sits in a file written after the build, which the store has no reference from.
    @Test func anImplicitInitializerInAFileTheStoreDoesNotCoverKeepsTheModulesInitializers() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("  uses resolved by the index store"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate3" + DiffAccessInitializerExposurePinsTests.implicitInit), "\(answer)")
    }

    /// An initializer of a module whose uncovered files call no initializer by implicit member keeps its suggestion.
    @Test func anInitializerOfAnotherModuleIsJudgedByTheStore() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("  + SproutKit.Pail.init()  Sources/SproutKit/Pail.swift:2  public → package: used only from GizmoTools, in this package"), "\(answer)")
    }
}

extension DiffAccessStoreImplicitInitPinsTests {
    /// `Seed`, built by implicit member in a `@frozen` enum case's default value.
    static let sprout = """
    public struct Seed {
        public init() {}
    }

    @frozen public enum Sprout {
        case grow(Seed = \(DiffAccessInitializerExposurePinsTests.implicitInit))
    }
    """

    /// `Crate3`, set on a holder whose property `Later.swift` assigns.
    static var crate: String {
        """
        public struct Crate3 {
            public init() {}
        }

        public struct Holder3 {
            public var crate: Crate3

            public init(crate: Crate3) {
                self.crate = crate
            }
        }
        """
    }

    /// An `@inlinable` function written after the build, building `Crate3` by implicit member without spelling it.
    static let later = """
    @inlinable public func refill(_ holder: inout Holder3) {
        holder.crate = \(DiffAccessInitializerExposurePinsTests.implicitInit)
    }
    """
}
