//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section never suggests narrower what a `@frozen` type's stored property names, in its type annotation or its initial value, whatever the property's own level: the compiler requires it to be public or `@usableFromInline`.
@Suite(.temporaryDirectories)
struct DiffAccessFrozenPinsTests {
    /// Narrowing `Pair2` fails with "type referenced from a stored property in a '@frozen' struct must be '@usableFromInline' or public", and narrowing its initializer fails the same way, though the property is private.
    @Test func whatAFrozenTypesPrivateStoredPropertyNamesKeepsItsLevel() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "public struct Pair2 {\n    public init() {}\n}\n\n@frozen public struct Frozen {\n    private var pair: Pair2 = Pair2()\n}\n")

        #expect(answer.contains("access: this range put 3 declarations at public; each has a use that needs its level"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Pair2  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Pair2.init"), "\(answer)")
    }

    /// Narrowing the type itself to `internal` fails with "'@frozen' attribute can only be applied to '@usableFromInline', package, or public declarations".
    @Test func aFrozenTypeIsNeverSuggestedBelowPackage() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "@frozen public struct Frozen {\n    var count = 0\n}\n")

        #expect(answer.contains("access: this range put 1 declaration at public; each has a use that needs its level"), "\(answer)")
    }

    /// A static property is not stored in the instance and a computed one has no storage, so what they name is judged by its uses as anywhere else.
    @Test func aFrozenTypesStaticAndComputedPropertiesExposeNothing() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: """
        public struct Tote {}

        @frozen public struct Frozen {
            static let spare: Tote = Tote()

            var copy: Tote {
                Tote()
            }
        }
        """)

        #expect(answer.contains("  + GizmoKit.Tote  Sources/GizmoKit/Added.swift:1  public → internal"), "\(answer)")
    }

    /// `Crate.init()` is called from `GizmoTools`, and in the `@frozen` type's initial value only by implicit member, which never spells `Crate`: the store's reference on that line keeps it public, where `package` fails with "initializer 'init()' is package and cannot be referenced from a property initializer in a '@frozen' type".
    @Test func aStoreReferenceInAFrozenTypesStoredPropertyKeepsItsLevel() async throws {
        let answer = try await Self.diffOfTheBuiltRange()

        #expect(answer.contains("semantic: fresh"), "\(answer)")
        #expect(answer.contains("  uses resolved by the index store"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate.init()"), "\(answer)")
    }

    /// Narrowing the initializer of `Crate2` fails with "initializer 'init()' is internal and cannot be referenced from a property initializer in a '@frozen' type", though the initial value never spells `Crate2`: name matching cannot tell which type the call builds, so it keeps every initializer of the module.
    @Test func anImplicitInitializerInAFrozenTypesStoredPropertyKeepsTheModulesInitializers() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: """
        public struct Crate2 {
            public init() {}
        }

        public struct Holder2 {
            public var crate: Crate2

            public init(crate: Crate2) {
                self.crate = crate
            }
        }

        @frozen public struct Snow {
            public var holder: Holder2 = \(Self.implicitInitializerCall.dropLast())crate: \(Self.implicitInitializerCall))

            public init() {}
        }
        """)

        #expect(answer.contains("uses name-matched over the working tree"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate2.init"), "\(answer)")
    }
}

extension DiffAccessFrozenPinsTests {
    /// An initializer called by implicit member, assembled so the fixture's text is not read as this file's own call.
    static let implicitInitializerCall = "." + "init()"

    /// The last commit's diff over a built package whose `@frozen` type calls an initializer by implicit member in a stored property's initial value.
    static func diffOfTheBuiltRange() async throws -> String {
        let fixture = try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "diff-access-frozen-store") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [.target(name: "GizmoKit"), .target(name: "GizmoTools", dependencies: ["GizmoKit"])]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.write("func run() {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write(
                """
                public struct Crate {
                    public init() {}
                }

                public struct Holder {
                    public let crate: Crate

                    public init(crate: Crate) {
                        self.crate = crate
                    }
                }

                @frozen public struct Frozen {
                    var holder: Holder = Holder(crate: \(Self.implicitInitializerCall))
                }
                """,
                to: "Sources/GizmoKit/Frozen.swift",
                in: root
            )
            try TestSources.write("import GizmoKit\n\nfunc run() {\n    _ = Crate()\n}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root, arguments: ["--target", "GizmoTools"])
        }
        return try await fixture.withEngine { engine in
            let range = try DiffRange.resolve("HEAD", git: GitContext(repoRoot: fixture.root))
            return try await engine.diff(options: DiffOptions(range: range), freshness: engine.ensureFresh())
        }
    }
}
