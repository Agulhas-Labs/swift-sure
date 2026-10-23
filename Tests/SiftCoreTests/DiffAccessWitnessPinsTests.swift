//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Whether a member may satisfy a protocol requirement, read from the index alone.
@Suite(.temporaryDirectories)
struct DiffAccessWitnessPinsTests {
    private static func witnesses(_ files: [String: String]) throws -> AccessWitnesses {
        let store = try TestSources.makeStore()
        let parsed = try files.sorted { $0.key < $1.key }.map { try TestSources.parsed($0.value, path: $0.key) }
        try store.replaceFiles(parsed) { _ in ("GizmoKit", false) }
        return AccessWitnesses(store: store)
    }

    private static func member(_ name: String, of container: String = "Gizmo", inheriting inherited: [String] = []) -> AccessSubject {
        AccessPinFixtures.subject(name, containerName: container, containerInherited: inherited)
    }

    @Test func aMarkerProtocolExcludesNothing() throws {
        let witnesses = try Self.witnesses(["Sources/GizmoKit/Gizmo.swift": "public struct Gizmo: Sendable {\n    public func restock() {}\n}\n"])

        for marker in ["Sendable", "BitwiseCopyable", "Copyable", "Escapable", "@unchecked Sendable", "~Copyable"] {
            #expect(try !witnesses.mayBeWitness(Self.member("restock()", inheriting: [marker])))
        }
    }

    @Test func aStandardLibraryProtocolExcludesOnlyTheMembersItsRequirementsName() throws {
        let witnesses = try Self.witnesses(["Sources/GizmoKit/Gizmo.swift": "public struct Gizmo: Hashable {\n    public func hash(into hasher: inout Hasher) {}\n    public func restock() {}\n}\n"])

        #expect(try witnesses.mayBeWitness(Self.member("hash(into:)", inheriting: ["Hashable"])))
        #expect(try !witnesses.mayBeWitness(Self.member("restock()", inheriting: ["Hashable"])))
    }

    @Test func aProtocolDeclaredOutsideTheRepositoryExcludesEveryMemberOfTheType() throws {
        let witnesses = try Self.witnesses(["Sources/GizmoKit/Gizmo.swift": "public struct Gizmo: Outsider {\n    public func restock() {}\n}\n"])

        #expect(try witnesses.mayBeWitness(Self.member("restock()", inheriting: ["Outsider"])))
        #expect(try witnesses.mayBeWitness(Self.member("anything()", inheriting: ["Outsider"])))
    }

    @Test func aProtocolDeclaredInTheRepositoryExcludesTheMembersNamedLikeARequirement() throws {
        let witnesses = try Self.witnesses([
            "Sources/GizmoKit/Gizmo.swift": "public struct Gizmo: Shelf {\n    public func restock() {}\n    public func shelve() {}\n}\n",
            "Sources/GizmoKit/Shelf.swift": "public protocol Shelf {\n    func restock()\n}\n",
        ])

        #expect(try witnesses.mayBeWitness(Self.member("restock()", inheriting: ["Shelf"])))
        #expect(try !witnesses.mayBeWitness(Self.member("shelve()", inheriting: ["Shelf"])))
    }

    @Test func theProtocolsAnInRepositoryProtocolInheritsAreFollowed() throws {
        let witnesses = try Self.witnesses([
            "Sources/GizmoKit/Gizmo.swift": "public struct Gizmo: Shelf {\n    public func hash(into hasher: inout Hasher) {}\n    public func shelve() {}\n}\n",
            "Sources/GizmoKit/Shelf.swift": "public protocol Shelf: Hashable {\n    func restock()\n}\n",
        ])

        #expect(try witnesses.mayBeWitness(Self.member("hash(into:)", inheriting: ["Shelf"])))
        #expect(try !witnesses.mayBeWitness(Self.member("shelve()", inheriting: ["Shelf"])))
    }

    @Test func aConformanceWrittenInAnExtensionElsewhereCounts() throws {
        let witnesses = try Self.witnesses([
            "Sources/GizmoKit/Gizmo.swift": "public struct Gizmo {\n    public func hash(into hasher: inout Hasher) {}\n    public func shelve() {}\n}\n",
            "Sources/GizmoKit/Gizmo+Hashable.swift": "extension Gizmo: Hashable {}\n",
        ])

        #expect(try witnesses.mayBeWitness(Self.member("hash(into:)")))
        #expect(try !witnesses.mayBeWitness(Self.member("shelve()")))
    }

    @Test func aTypeWithNoConformancesHasNoWitnesses() throws {
        let witnesses = try Self.witnesses(["Sources/GizmoKit/Gizmo.swift": "public struct Gizmo {\n    public func restock() {}\n}\n"])

        #expect(try !witnesses.mayBeWitness(Self.member("restock()")))
    }

    @Test func aTopLevelDeclarationOrANestedTypeNoAssociatedTypeNamesIsNoWitness() throws {
        let witnesses = try Self.witnesses(["Sources/GizmoKit/Gizmo.swift": "public struct Gizmo: Hashable {}\n"])

        #expect(try !witnesses.mayBeWitness(AccessPinFixtures.subject("restock()")))
        #expect(try !witnesses.mayBeWitness(AccessPinFixtures.subject("Inner", kind: .structKind, containerName: "Gizmo", containerInherited: ["Hashable"])))
    }
}
