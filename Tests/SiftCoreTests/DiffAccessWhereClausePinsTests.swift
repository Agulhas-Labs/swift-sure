//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section never suggests narrower a type an extension's `where` clause names below that extension's widest member or its own written level, since its members are visible no wider than its requirements.
@Suite(.temporaryDirectories)
struct DiffAccessWhereClausePinsTests {
    /// Narrowing `Coin` fails with "cannot declare a public instance method in an extension with internal requirements".
    @Test func aTypeInAnExtensionsWhereClauseKeepsItsPublicMembersLevel() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "public struct Coin {}\n\nextension Array where Element == Coin {\n    public func total() -> Int {\n        count\n    }\n}\n")

        #expect(answer.contains("access: this range put 2 declarations at public"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Coin  "), "\(answer)")
    }

    /// Narrowing `Stamp` fails the same way: a constrained conformance's `where` clause is the extension's requirement too.
    @Test func aProtocolInAConstrainedConformancesWhereClauseKeepsItsLevel() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: """
        public protocol Stamp {}

        public protocol Sealed {}

        public struct Box<T> {}

        extension Box: Sealed where T: Stamp {
            public func seal() {}
        }
        """)

        #expect(!answer.contains("GizmoKit.Stamp  "), "\(answer)")
    }

    /// Narrowing `Coin` fails with "extension cannot be declared public because its generic requirement uses an internal type", though the extension has no member.
    @Test func aTypeInAPublicExtensionsWhereClauseKeepsItsLevel() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "public struct Coin {}\n\npublic extension Array where Element == Coin {}\n")

        #expect(answer.contains("access: this range put 1 declaration at public; each has a use that needs its level"), "\(answer)")
    }

    /// An extension with no member and no written level requires nothing visible, so what its `where` clause names is judged by its uses.
    @Test func anEmptyConstrainedConformanceExposesNothing() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "public protocol Stamp {}\n\npublic protocol Sealed {}\n\npublic struct Box<T> {}\n\nextension Box: Sealed where T: Stamp {}\n")

        #expect(answer.contains("  + GizmoKit.Stamp  Sources/GizmoKit/Added.swift:1  public → internal"), "\(answer)")
    }

    /// An extension of the type itself sits inside it, so narrowing the type caps its members too and they expose nothing about it.
    @Test func aTypesOwnExtensionExposesNothingAboutIt() async throws {
        let answer = try await DiffAccessExposurePinsTests.diff(adding: "public struct Coin {}\n\nextension Coin {\n    public func total() -> Int {\n        0\n    }\n}\n")

        #expect(answer.contains("  + GizmoKit.Coin  Sources/GizmoKit/Added.swift:1  public → internal"), "\(answer)")
    }
}
