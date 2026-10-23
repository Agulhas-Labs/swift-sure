//
// Copyright © Agulhas Labs
//

/// The test `where` and `digest` both read a type as declared outside the repository by: a path or package dependency's type, whose sources the index never holds.
///
/// A type is external where the index holds no type, typealias or associated type of the name, and the repository writes it: by an extension, or by a use as a type that means no generic parameter, associated type or body-local type declared around it, nor, written as a qualifier in a file importing a module of the name, that module. The index answers the first half; the working tree's type uses answer the second, so a caller scans them only once the index has left the type undeclared and unextended.
struct ExternalTypeTest {
    /// The index whose declarations and file imports the test reads.
    let store: IndexStore

    /// Whether the index holds no declaration of `type` other than extensions of it.
    func indexDeclaresNothing(named type: String) throws -> Bool {
        try store.symbols(named: type).allSatisfy { $0.kind == .extensionKind }
    }

    /// Whether one of `sites`, the working tree's uses of `type` as a type, writes the type itself rather than a generic parameter, an associated type, a body-local type or an imported module of the name.
    func writesTheType(_ type: String, at sites: [SyntacticCallSite]) throws -> Bool {
        var importsType: [String: Bool] = [:]
        for site in sites where !site.meansLocalType && !site.meansOwnAssociatedType {
            // The name written as a qualifier, `Net.URL`, in a file importing a module of the name is that module, as an extension's placement reads it; written bare there, `let net: Net`, it is the type.
            if site.qualifiesAName {
                let imports = try importsType[site.path] ?? (store.fileRow(path: site.path)?.imports.contains(type) == true)
                importsType[site.path] = imports
                if imports {
                    continue
                }
            }
            if try !isGenericParameter(type, writtenAt: site) {
                return true
            }
        }
        return false
    }

    /// Whether `type`, written bare at `site`, is a generic parameter of a type the site is written in — `T` in an extension of `struct Box<T>`, which that declaration's generic clause declares.
    ///
    /// A generic clause written around the site itself, a function's or a type's, is never asked about: the scan records no bare use of a name such a clause binds.
    private func isGenericParameter(_ type: String, writtenAt site: SyntacticCallSite) throws -> Bool {
        guard site.qualifier == nil else { return false }
        return try site.enclosingTypes.contains { enclosing in
            try store.typeDeclarations(named: DeclaredTypeName.last(ofPath: enclosing)).contains { declaration in
                SameNamedTypes.Resolver.genericParameters(of: declaration).contains(type)
            }
        }
    }
}
