//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section keeps an initializer at the level a head's parameter default value needs, and only that: a head's `==` or a static property's initial value calls nothing a client compiles.
///
/// Nothing outside the module uses any of these declarations by name, so an initializer nothing exposes reads `public → internal`.
@Suite(.temporaryDirectories)
struct DiffAccessInitializerExposurePinsTests {
    /// Narrowing `Bin.init()` builds: the `==` beside it takes two values and calls no initializer.
    @Test func anOperatorInItsOwnTypeDoesNotExposeAnInitializer() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: """
        public struct Bin: Equatable {
            public init() {}

            public static func == (lhs: Bin, rhs: Bin) -> Bool {
                true
            }
        }
        """)

        #expect(answer.contains("  + GizmoKit.Bin.init()  Sources/GizmoKit/Added.swift:2  public → internal"), "\(answer)")
    }

    /// Narrowing the initializer of `Tote` builds: a static property's initial value is not compiled into clients.
    @Test func aStaticPropertysInitialValueDoesNotExposeAnInitializer() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "public struct Tote {\n    public init() {}\n\n    public static let empty = Self()\n}\n")

        #expect(answer.contains("  + GizmoKit.Tote.init()  Sources/GizmoKit/Added.swift:2  public → internal"), "\(answer)")
    }

    /// Narrowing the initializer fails with "initializer 'init()' is internal and cannot be referenced from a default argument value": the parameter's type names what the implicit-member call builds.
    @Test func anImplicitInitializerInADefaultValueOfItsTypeKeepsItsLevel() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "public struct Bin {\n    public init() {}\n}\n\npublic func fill(bin: Bin = \(Self.implicitInit)) {}\n")

        #expect(answer.contains("access: this range put 3 declarations at public, 1 with no use outside module GizmoKit"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Bin.init"), "\(answer)")
    }

    /// Narrowing the initializer fails with "initializer 'init()' is internal and cannot be referenced from an '@inlinable' function", though the body never spells `Crate`: name matching cannot tell which type the call builds, so it keeps every initializer of the module.
    @Test func anImplicitInitializerInAnInlinableBodyKeepsTheModulesInitializers() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: """
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
            holder.crate = \(Self.implicitInit)
        }
        """)

        #expect(answer.contains("uses name-matched over the working tree"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate.init"), "\(answer)")
    }

    /// Narrowing the initializer fails with "initializer 'init()' is internal and cannot be referenced from a default argument value", though the default value never spells `Tote`.
    @Test func anImplicitInitializerNestedInADefaultValueKeepsTheModulesInitializers() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: """
        public struct Tote {
            public init() {}
        }

        public struct Pouch {
            public var tote: Tote

            public init(tote: Tote) {
                self.tote = tote
            }
        }

        public func carry(_ pouch: Pouch = Pouch(tote: \(Self.implicitInit))) {}
        """)

        #expect(answer.contains("uses name-matched over the working tree"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Tote.init"), "\(answer)")
    }

    /// Narrowing the initializer fails with "initializer 'init()' is internal and cannot be referenced from a default argument value": an enum case's associated value is a parameter whose type names what the implicit-member call builds.
    @Test func anImplicitInitializerInAnEnumCasesDefaultValueKeepsItsLevel() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: """
        public struct Seed {
            public init() {}
        }

        @frozen public enum Sprout {
            case grow(Seed = \(Self.implicitInit))
        }
        """)

        #expect(answer.contains("uses name-matched over the working tree"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Seed.init"), "\(answer)")
    }
}

extension DiffAccessInitializerExposurePinsTests {
    /// An initializer called by implicit member with no arguments, written in two halves so the lint rule against that shorthand in this repository's own code does not read a fixture's text as code.
    static let implicitInit = "." + "init()"
}
