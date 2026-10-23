//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers a typealias's name that a generic parameter or an `#if` clause leaves to something else, with no index store.
///
/// A nested alias writing a name its type's generic parameter declares names the parameter, not the asked type. An alias declared only inside an `#if` clause hides an outer declaration of the name only in the builds compiling it, and a use in an extension of a type declared only inside an `#if` clause sees what that type declares.
@Suite(.temporaryDirectories)
struct WhereAliasGenericClauseTests {
    private static var types: String {
        """
        import AppKit

        struct Gizmo {
            init(_ name: String) {}
        }
        struct Other {
            init(_ name: String) {}
        }
        """
    }

    private static func lookup(declaring declarations: String, calling calls: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(declarations, to: "Sources/App/Types.swift", in: root)
        try TestSources.write(calls, to: "Sources/App/Calls.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let engine = try SiftEngine(directory: root)
        let freshness = try await engine.ensureFresh()
        let output = try await engine.lookup(symbol: "Gizmo", freshness: freshness)
        #expect(!output.contains("parse errors"), "\(output)", sourceLocation: sourceLocation)
        return output
    }

    /// A nested alias writing its type's generic parameter names whatever the type is specialised with, so a call through it is no use of the top-level alias of the same name.
    @Test
    func anAliasWritingItsTypesGenericParameterIsNotFoldedIn() async throws {
        let output = try await Self.lookup(
            declaring: Self.types + "\n" + """
            typealias Crate = Gizmo
            class Panel<Crate>: NSObject {
                typealias Bin = Crate
            }
            """,
            calling: "func f() { _ = Panel<Other>.Bin(\"t\") }"
        )

        #expect(!output.contains("Panel.Bin"), "\(output)")
    }

    /// A member alias of the type declared only inside an `#if` clause leaves the name to the top-level alias of another type in the builds without it, so a use below it is kept, not proven.
    @Test
    func aUseBelowAMemberAliasOfTheTypeInsideAnIfClauseIsNotProven() async throws {
        let output = try await Self.lookup(
            declaring: Self.types + "\n" + """
            typealias Crate = Other
            enum Space {
                #if DEBUG
                typealias Crate = Gizmo
                #endif
                static func make() { _ = Crate("t") }
            }
            """,
            calling: "struct Shop {}"
        )

        #expect(output.contains("kept as a use though not proven to name it"), "\(output)")
        #expect(output.contains("static func make() { _ = Crate(\"t\") }"), "\(output)")
    }

    /// An extension of a type declared only inside an `#if` clause compiles only where the type's own `Crate` names another type, so a use in it is not the top-level alias's.
    @Test
    func aUseInAnExtensionOfATypeDeclaredInsideAnIfClauseIsNotTheTopLevelAlias() async throws {
        let output = try await Self.lookup(
            declaring: Self.types + "\n" + """
            typealias Crate = Gizmo
            #if DEBUG
            enum Space {
                typealias Crate = Other
            }
            #endif
            """,
            calling: """
            extension Space {
                static func make() { _ = Crate("t") }
            }
            """
        )

        #expect(!output.contains("static func make() { _ = Crate(\"t\") }"), "\(output)")
        #expect(output.contains("1 more line writing \"Crate\" bare inside a type that declares its own \"Crate\""), "\(output)")
    }

    /// A type declared once per `#if` clause, one copy declaring its own alias of the name only under a further clause, leaves a use in an extension of it to the top-level alias in the builds compiling neither clause, so the use stays in the answer.
    @Test
    func aUseInAnExtensionOfATypeWhoseCopyDeclaresTheNameOnlyUnderAClauseIsKept() async throws {
        let output = try await Self.copyDeclaringTheNameOnlyUnderAClause()

        #expect(output.contains("static func make() { _ = Crate(\"t\") }"), "\(output)")
    }

    /// The same use is only one some builds make, so it is kept as not proven.
    @Test
    func aUseInAnExtensionOfATypeWhoseCopyDeclaresTheNameOnlyUnderAClauseIsNotProven() async throws {
        let output = try await Self.copyDeclaringTheNameOnlyUnderAClause()

        #expect(output.contains("kept as a use though not proven to name it"), "\(output)")
        #expect(output.contains("static func make() { _ = Crate(\"t\") }"), "\(output)")
    }

    /// The where answer for a use in an extension of a type declared once per `#if` clause, one copy declaring its own alias of the name only under a further clause.
    private static func copyDeclaringTheNameOnlyUnderAClause(sourceLocation: SourceLocation = #_sourceLocation) async throws -> String {
        try await lookup(
            declaring: types + "\n" + """
            typealias Crate = Gizmo
            #if DEBUG
            enum Space {
                typealias Crate = Other
            }
            #else
            enum Space {
                #if X
                typealias Crate = Other
                #endif
            }
            #endif
            """,
            calling: """
            extension Space {
                static func make() { _ = Crate("t") }
            }
            """,
            sourceLocation: sourceLocation
        )
    }

    /// The builds without a member alias declared only inside an `#if` clause find the name in the superclass before the top level, and the superclass's alias names the type too, so the use is proven.
    @Test
    func theBuildsWithoutAMemberAliasInsideAnIfClauseFindTheInheritedOne() async throws {
        let output = try await Self.lookup(
            declaring: Self.types + "\n" + """
            typealias Crate = Other
            class Base {
                typealias Crate = Gizmo
            }
            class Space: Base {
                #if DEBUG
                typealias Crate = Gizmo
                #endif
                static func make() { _ = Crate("t") }
            }
            """,
            calling: "struct Shop {}"
        )

        #expect(!output.contains("kept as a use though not proven to name it"), "\(output)")
        #expect(output.contains("static func make() { _ = Crate(\"t\") }"), "\(output)")
    }
}
