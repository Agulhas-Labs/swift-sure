//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with a fresh index store keeps a declaration public where the store records a reference to it inside an `@inlinable` declaration or a parameter's default value, however that reference is spelled, and judges the rest by the store's uses.
@Suite(.temporaryDirectories, .serialized)
struct DiffAccessStoreExposurePinsTests {
    /// A built package whose last commit adds initializers called from another module, two of them also called by implicit member from fragile code in their own module.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "diff-access-store-exposure") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [
                        .target(name: "GizmoKit"),
                        .target(name: "GizmoTools", dependencies: ["GizmoKit"]),
                    ]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.write("func run() {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write(Self.crate, to: "Sources/GizmoKit/Crate.swift", in: root)
            try TestSources.write(Self.tote, to: "Sources/GizmoKit/Tote.swift", in: root)
            try TestSources.write("public struct Pail {\n    public init() {}\n}\n", to: "Sources/GizmoKit/Pail.swift", in: root)
            try TestSources.write("import GizmoKit\n\nfunc run() {\n    _ = Crate()\n    _ = Tote()\n    _ = Pail()\n}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root)
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

    /// Narrowing `Crate.init()` to `package` fails with "initializer 'init()' is package and cannot be referenced from an '@inlinable' function": the store records the implicit-member call inside `reset(_:)`.
    @Test func aReferenceInAnInlinableBodyKeepsItsLevel() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("semantic: fresh"), "\(answer)")
        #expect(answer.contains("  uses resolved by the index store"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate.init()"), "\(answer)")
    }

    /// Narrowing `Tote.init()` to `package` fails with "initializer 'init()' is package and cannot be referenced from a default argument value".
    @Test func aReferenceInADefaultValueKeepsItsLevel() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(!answer.contains("GizmoKit.Tote.init()"), "\(answer)")
    }

    /// An initializer only called from another module keeps its suggestion: the store's references say which initializer each call builds, so no implicit-member call elsewhere in the module holds it back.
    @Test func anInitializerNoFragileCodeReferencesIsJudged() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("  + GizmoKit.Pail.init()  Sources/GizmoKit/Pail.swift:2  public → package: used only from GizmoTools, in this package"), "\(answer)")
    }
}

extension DiffAccessStoreExposurePinsTests {
    /// `Crate`, built by implicit member in an `@inlinable` function that never spells it.
    static let crate = """
    public struct Crate {
        public init() {}
    }

    public struct Holder {
        public var crate: Crate

        public init(crate: Crate) {
            self.crate = crate
        }
    }

    @inlinable public func reset(_ holder: inout Holder) {
        holder.crate = \(DiffAccessInitializerExposurePinsTests.implicitInit)
    }
    """

    /// `Tote`, built by implicit member inside another type's call in a parameter's default value.
    static let tote = """
    public struct Tote {
        public init() {}
    }

    public struct Pouch {
        public var tote: Tote

        public init(tote: Tote) {
            self.tote = tote
        }
    }

    public func carry(_ pouch: Pouch = Pouch(tote: \(DiffAccessInitializerExposurePinsTests.implicitInit))) {}
    """
}
