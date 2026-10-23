//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section over conformances it cannot fully see without a store: the sequence and collection protocols, associated-type witnesses, and a container's attributes declared in another file.
///
/// Each test commits a package, edits the working tree and reads the diff of the working tree, so every use is name-matched.
@Suite(.temporaryDirectories)
struct DiffAccessConformancePinsTests {
    /// A collection's customization points are too many to list, so every member of a type conforming to one is a witness and none is judged: narrowing `startIndex` would not build.
    @Test func everyMemberOfACollectionIsAWitness() async throws {
        let root = try DiffAccessRepoPinsTests.depot()
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write("""
        public struct Ring: BidirectionalCollection {
            public var startIndex: Int { 0 }
            public var endIndex: Int { 3 }
            public var count: Int { 3 }
            public func index(after position: Int) -> Int { position + 1 }
            public func index(before position: Int) -> Int { position - 1 }
            public subscript(position: Int) -> Int { position }
        }

        """, to: "Sources/GizmoKit/Ring.swift", in: root)

        let section = try await DiffAccessRepoPinsTests.section(of: DiffEngineTests.diff(root))

        #expect(section == [
            "access: this range put 1 declaration at public, 1 with no use outside module GizmoKit",
            "  uses name-matched over the working tree, which can miss a use through a typealias, a closure or a macro",
            "  + GizmoKit.Ring  Sources/GizmoKit/Ring.swift:1  public → internal: no use by that name outside module GizmoKit",
            "  not judged: 5 protocol witnesses, 1 reached by the compiler, not by name",
        ])
    }

    /// A typealias satisfying a sequence's associated type is a witness, as every member of a sequence is.
    @Test func aSequencesTypealiasIsAWitness() async throws {
        let root = try DiffAccessRepoPinsTests.depot()
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write("""
        public struct Bag: Sequence {
            public typealias Element = Int
            public func makeIterator() -> IndexingIterator<[Int]> { [1, 2].makeIterator() }
        }

        """, to: "Sources/GizmoKit/Bag.swift", in: root)

        let section = try await DiffAccessRepoPinsTests.section(of: DiffEngineTests.diff(root))

        #expect(section.contains("  not judged: 2 protocol witnesses"), "\(section)")
        #expect(!section.contains { $0.contains("Bag.Element") }, "\(section)")
    }

    /// A typealias named like an associated type of a listed protocol is a witness; a nested type named like none is judged.
    @Test func aListedProtocolsAssociatedTypeIsAWitness() async throws {
        let root = try DiffAccessRepoPinsTests.depot()
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write("""
        public struct Tally: IteratorProtocol {
            public typealias Element = Int
            public enum Mode {}
            public mutating func next() -> Int? { nil }
        }

        """, to: "Sources/GizmoKit/Tally.swift", in: root)

        let section = try await DiffAccessRepoPinsTests.section(of: DiffEngineTests.diff(root))

        #expect(section.contains("  + GizmoKit.Tally.Mode  Sources/GizmoKit/Tally.swift:3  public → internal: no use by that name outside module GizmoKit"), "\(section)")
        #expect(section.contains("  not judged: 2 protocol witnesses"), "\(section)")
        #expect(!section.contains { $0.contains("Tally.Element") }, "\(section)")
    }

    /// A nested type named like an associated type of a protocol this repository declares is a witness, counted as not judged rather than as needing its level.
    @Test func aNestedTypeSatisfyingARepositoryAssociatedTypeIsAWitness() async throws {
        let root = try DiffAccessRepoPinsTests.depot()
        try TestSources.write("public protocol Stocking {\n    associatedtype Item\n    func restock() -> Item\n}\n", to: "Sources/GizmoKit/Stocking.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("""
        public struct Shelf: Stocking {
            public struct Item {}
            public func restock() -> Item { Item() }
        }

        """, to: "Sources/GizmoKit/Shelf.swift", in: root)

        let section = try await DiffAccessRepoPinsTests.section(of: DiffEngineTests.diff(root))

        #expect(section.contains("  not judged: 2 protocol witnesses"), "\(section)")
        #expect(!section.contains { $0.contains("Shelf.Item") }, "\(section)")
    }

    /// A result builder's `build…` method in an extension in its own file is reached by the compiler: the type's `@resultBuilder` is read from the index.
    @Test func aResultBuilderMethodInAnotherFileIsNotJudged() async throws {
        let root = try DiffAccessRepoPinsTests.depot()
        try TestSources.write("""
        @resultBuilder public struct Stack {
            public static func buildExpression(_ value: Int) -> [Int] { [value] }
            public static func buildBlock(_ parts: [Int]...) -> [Int] { Array(parts.joined()) }
        }

        """, to: "Sources/GizmoKit/Stack.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("extension Stack {\n    public static func buildOptional(_ part: [Int]?) -> [Int] { part ?? [] }\n}\n", to: "Sources/GizmoKit/Stack+Optional.swift", in: root)

        let section = try await DiffAccessRepoPinsTests.section(of: DiffEngineTests.diff(root))

        #expect(section == [
            "access: none of the declarations this range put at open, public or package could be judged",
            "  not judged: 1 reached by the compiler, not by name",
        ])
    }

    /// A property wrapper's `projectedValue` in an extension in its own file is reached by the compiler: the type's `@propertyWrapper` is read from the index.
    @Test func aPropertyWrapperValueInAnotherFileIsNotJudged() async throws {
        let root = try DiffAccessRepoPinsTests.depot()
        try TestSources.write("""
        @propertyWrapper public struct Boxed {
            public var wrappedValue: Int
            public init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
        }

        """, to: "Sources/GizmoKit/Boxed.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("extension Boxed {\n    public var projectedValue: Int { wrappedValue }\n}\n", to: "Sources/GizmoKit/Boxed+Projected.swift", in: root)

        let section = try await DiffAccessRepoPinsTests.section(of: DiffEngineTests.diff(root))

        #expect(section == [
            "access: none of the declarations this range put at open, public or package could be judged",
            "  not judged: 1 reached by the compiler, not by name",
        ])
    }

    /// A nested type of a type conforming to a protocol whose requirements cannot be seen may satisfy one of its associated types, so it is a witness like every other member.
    @Test func aNestedTypeOfAnUnseenProtocolsConformerIsAWitness() throws {
        let store = try TestSources.makeStore()
        try store.replaceFiles([TestSources.parsed("public struct Gizmo: Outsider {\n    public struct Inner {}\n}\n", path: "Sources/GizmoKit/Gizmo.swift")]) { _ in ("GizmoKit", false) }

        #expect(try AccessWitnesses(store: store).mayBeWitness(AccessPinFixtures.subject("Inner", kind: .structKind, containerName: "Gizmo", containerInherited: ["Outsider"])))
    }

    /// Each listed protocol's entry holds every member and associated type of the protocols it inherits, and each protocol it inherits is listed or a marker.
    @Test func eachListedProtocolHoldsItsInheritedRequirements() {
        for (name, listed) in StandardLibraryRequirements.protocols {
            for parent in listed.inherits {
                guard let inherited = StandardLibraryRequirements.protocols[parent] else {
                    #expect(StandardLibraryRequirements.markers.contains(parent), "\(name) inherits \(parent)")
                    continue
                }
                #expect(listed.members.isSuperset(of: inherited.members), "\(name) lacks \(inherited.members.subtracting(listed.members)) from \(parent)")
                #expect(listed.associatedTypes.isSuperset(of: inherited.associatedTypes), "\(name) lacks \(parent)'s associated types")
            }
        }
    }
}
