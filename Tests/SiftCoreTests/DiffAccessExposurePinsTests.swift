//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section never suggests narrower a declaration a wider one exposes, whether it is named in that declaration's signature, inheritance clause, generic constraint or default argument, or in an `@inlinable` body.
///
/// Nothing outside the module uses any of these declarations by name, so each exposed one would otherwise read `public → internal`; it is counted as having a use that needs its level and gets no line.
@Suite(.temporaryDirectories)
struct DiffAccessExposurePinsTests {
    @Test func aTypeNamedInAPublicSignatureKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public struct Part {}\n\npublic func make() -> Part {\n    Part()\n}\n")

        #expect(answer.contains("access: this range put 2 declarations at public, 1 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.make()  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Part  "), "\(answer)")
    }

    @Test func aProtocolInAPublicTypesInheritanceClauseKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public protocol Shape {}\n\npublic struct Tray: Shape {}\n")

        #expect(answer.contains("access: this range put 2 declarations at public, 1 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.Tray  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Shape  "), "\(answer)")
    }

    @Test func protocolsInAPublicFunctionsGenericConstraintsKeepTheirLevel() async throws {
        let answer = try await Self.diff(adding: """
        public protocol Rule {}

        public protocol Gauge {}

        public func check<T: Rule, U>(_ value: T, _ other: U) where U: Gauge {}
        """)

        #expect(answer.contains("access: this range put 3 declarations at public, 1 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.check(_:_:)  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Rule  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Gauge  "), "\(answer)")
    }

    @Test func aPropertyInAPublicDefaultArgumentKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public enum Bin {\n    public static let size = 4\n}\n\npublic func fill(count: Int = Bin.size) {}\n")

        #expect(answer.contains("access: this range put 3 declarations at public, 1 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.fill(count:)  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Bin.size  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Bin  "), "\(answer)")
    }

    /// The `@inlinable` function itself is never judged; what its body names keeps its level.
    @Test func whatAnInlinableBodyNamesKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public enum Crate {\n    public static func seal() {}\n}\n\n@inlinable public func pack() {\n    Crate.seal()\n}\n")

        #expect(answer.contains("access: this range put 2 declarations at public; each has a use that needs its level"), "\(answer)")
        #expect(answer.contains("  not judged: 1 @inlinable or @usableFromInline"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate"), "\(answer)")
    }

    /// Narrowing the initializer fails with "initializer 'init()' is internal and cannot be referenced from a default argument value".
    @Test func anInitializerCalledInAPublicDefaultArgumentKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public struct Bin {\n    public init() {}\n}\n\npublic func fill(bin: Bin = Bin()) {}\n")

        #expect(answer.contains("access: this range put 3 declarations at public, 1 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.fill(bin:)  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Bin.init"), "\(answer)")
    }

    /// Narrowing the initializer fails with "initializer 'init()' is internal and cannot be referenced from an '@inlinable' function".
    @Test func anInitializerCalledInAnInlinableBodyKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public struct Crate {\n    public init() {}\n}\n\n@inlinable public func make() -> Crate {\n    Crate()\n}\n")

        #expect(answer.contains("access: this range put 2 declarations at public; each has a use that needs its level"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate.init"), "\(answer)")
    }

    /// Inside its own type an initializer is called as `Self()`, which never spells the type's name.
    @Test func anInitializerCalledAsSelfInItsOwnTypesInlinableMemberKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public struct Pail {\n    public init() {}\n\n    @inlinable public static func make() -> Self {\n        Self()\n    }\n}\n")

        #expect(!answer.contains("GizmoKit.Pail.init"), "\(answer)")
    }

    /// Another initializer's own head and body spell `init` without calling this one, so they never expose it.
    @Test func anInitializerIsNotExposedByItsSiblingInitializersOwnHead() async throws {
        let answer = try await Self.diff(adding: "public struct Bin {\n    public init() {}\n\n    @inlinable public init(size: Int = 3) {}\n}\n")

        #expect(answer.contains("  + GizmoKit.Bin.init()  Sources/GizmoKit/Added.swift:2  public → internal"), "\(answer)")
    }

    /// Narrowing `Tote` fails with "the parameter of a '@usableFromInline' function must be '@usableFromInline' or public", though the function itself is internal.
    @Test func aTypeNamedInAnInternalUsableFromInlineSignatureKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public struct Tote {}\n\n@usableFromInline internal func stash(_ tote: Tote) {}\n")

        #expect(answer.contains("access: this range put 1 declaration at public; each has a use that needs its level"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Tote  "), "\(answer)")
    }

    /// Narrowing `wrap()` fails with "global function 'wrap()' is internal and cannot be referenced from an '@inlinable' function", though the function inlining it is internal.
    @Test func whatAnInternalInlinableBodyNamesKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public func wrap() -> Int {\n    1\n}\n\n@inlinable internal func pack() -> Int {\n    wrap()\n}\n")

        #expect(answer.contains("access: this range put 1 declaration at public; each has a use that needs its level"), "\(answer)")
        #expect(!answer.contains("GizmoKit.wrap()  "), "\(answer)")
    }

    /// Narrowing a type caps its own members and extensions with it, so what they name of it needs no level.
    @Test func aTypeNamedOnlyByItsOwnMembersIsJudged() async throws {
        let answer = try await Self.diff(adding: """
        public struct Box3 {
            public static func + (lhs: Box3, rhs: Box3) -> Box3 {
                lhs
            }
        }

        extension Box3 {
            public func copy() -> Box3 {
                self
            }
        }
        """)

        #expect(answer.contains("access: this range put 2 declarations at public, 2 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.Box3  Sources/GizmoKit/Added.swift:1  public → internal"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.Box3.copy()  "), "\(answer)")
    }

    /// Narrowing `Inner` fails with "method cannot be declared public because its result uses an internal type": its container's member is not inside it.
    @Test func aNestedTypeNamedInItsContainersPublicSignatureKeepsItsLevel() async throws {
        let answer = try await Self.diff(adding: "public struct Outer {\n    public struct Inner {}\n\n    public func make() -> Inner {\n        Inner()\n    }\n}\n")

        #expect(answer.contains("access: this range put 3 declarations at public, 2 with no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.Outer  "), "\(answer)")
        #expect(!answer.contains("GizmoKit.Outer.Inner  "), "\(answer)")
    }
}

extension DiffAccessExposurePinsTests {
    /// The diff of a working tree that adds `source` to `GizmoKit` in a committed package nothing else uses it from.
    static func diff(adding source: String) async throws -> String {
        let root = try DiffAccessRepoPinsTests.depot()
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write(source, to: "Sources/GizmoKit/Added.swift", in: root)
        return try await DiffEngineTests.diff(root)
    }
}
