//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a member may satisfy a requirement of a protocol its type conforms to, read from the index when no store answers.
///
/// A type's conformances are its own clause, its extensions' anywhere in the index, and the protocols those inherit. A marker protocol excludes nothing, a standard-library protocol in ``StandardLibraryRequirements`` only the members its requirements name, a protocol declared in this repository the members named like one of its requirements, and a sequence or collection protocol or any other protocol every member, since its requirements cannot all be seen. A nested type or typealias is matched against associated types, every other member against the rest.
struct AccessWitnesses {
    let store: IndexStore

    func mayBeWitness(_ subject: AccessSubject) throws -> Bool {
        guard let container = subject.containerName else { return false }
        let isType = subject.kind.isTypeDeclaration || subject.kind == .typealiasKind
        var pending = subject.containerInherited
        for row in try store.typeDeclarations(named: container) + store.extensions(ofTypeNamed: container) {
            pending += try store.inheritedNames(of: row.id)
            // A protocol extension's member is a default implementation of a requirement of that protocol.
            if row.kind == .protocolKind {
                pending.append(container)
            }
        }
        var seen: Set<String> = []
        while let written = pending.popLast() {
            guard let name = Self.protocolName(written), seen.insert(name).inserted else { continue }
            if StandardLibraryRequirements.markers.contains(name) {
                continue
            }
            if StandardLibraryRequirements.unlisted.contains(name) {
                return true
            }
            if let listed = StandardLibraryRequirements.protocols[name] {
                if (isType ? listed.associatedTypes : listed.members).contains(subject.name) {
                    return true
                }
                pending += listed.inherits
                continue
            }
            let declared = try store.typeDeclarations(named: name)
            if declared.isEmpty {
                return true
            }
            for row in declared where row.kind == .protocolKind {
                if try store.children(of: row.id).contains(where: { $0.name == subject.name && ($0.kind == .associatedType) == isType }) {
                    return true
                }
                pending += try store.inheritedNames(of: row.id)
            }
        }
        return false
    }

    /// The simple name an inheritance entry names, `nil` for a suppressed one (`~Copyable`).
    static func protocolName(_ written: String) -> String? {
        var text = written.trimmingCharacters(in: .whitespaces)
        for prefix in ["@unchecked ", "@preconcurrency ", "@retroactive ", "any "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty, !text.hasPrefix("~") else { return nil }
        return DeclaredTypeName.last(ofPath: text)
    }
}
