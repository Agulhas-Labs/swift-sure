//
// Copyright © Agulhas Labs
//

import Foundation

/// One name a working-tree walk scans for: the base name a site spells, the module declaring it, and the kind of declaration it names, which decides the shape of the sites that count.
struct AffectedNameSeed: Hashable, Sendable {
    let name: String
    let module: String
    let kind: SymbolKind
    /// The one file the name can be written in, for a `private` or `fileprivate` declaration; `nil` where it is visible beyond its file.
    var file: String?

    /// The seed for an indexed declaration by its own base name.
    static func of(_ row: SymbolRow, in store: IndexStore) throws -> AffectedNameSeed {
        try AffectedNameSeed(name: row.baseName, module: row.module, kind: row.kind, file: fileScope(of: row, in: store))
    }

    /// The file a declaration's name is confined to: its own, where it is `private` or `fileprivate`, since no other file can spell it.
    ///
    /// A member is confined only where it can witness no protocol requirement called through the protocol from another file (`spinner.whirl()`): nothing in its file writes an inheritance clause. A conformance a `fileprivate` member witnesses has to be written in its own file, on the type, a subclass inheriting the member or an extension, so the clause is there whichever type or protocol extension declares the member; a generic constraint's colon counts too, which only leaves a name unconfined. A declaration at file scope witnesses nothing.
    static func fileScope(of row: SymbolRow, in store: IndexStore) throws -> String? {
        guard row.accessLevel <= .fileprivateLevel else { return nil }
        guard try !store.parentChain(of: row).isEmpty else { return row.path }
        let inherits = try store.symbols(inFile: row.path).contains { ($0.kind.isTypeDeclaration || $0.kind == .extensionKind) && $0.signature.contains(":") }
        return inherits ? nil : row.path
    }

    /// The shape a call site of this seed takes: a type, a typealias or an associated type is reached wherever its name is written as one, and anything else as `where` scans a declaration of its kind, a function by a call or by being named unapplied.
    ///
    /// A function's bare name with no call and no labels, `x.gate`, is no site of it here, as `where` counts it beside its list rather than in it: the walk drops it (`AffectedRenderer.sites`), since it is far more often a same-named property of another type than a function handed on unapplied, and on a rename it carried the walk across most of a target.
    var shape: CallSiteScanner.SiteShape {
        if kind.isTypeDeclaration || kind == .extensionKind || kind == .typealiasKind || kind == .associatedType {
            return .typeUse
        }
        return .of(kind, sharing: nil)
    }

    /// The seed for an indexed declaration as a call site spells it: an initializer is called through its type, so it is the type's name.
    static func callSite(of row: SymbolRow, in store: IndexStore) throws -> AffectedNameSeed {
        guard row.kind == .initializer, let type = try store.parentChain(of: row).last else {
            return try of(row, in: store)
        }
        return try AffectedNameSeed(name: DeclaredTypeName.last(ofPath: type.name), module: row.module, kind: .initializer, file: fileScope(of: row, in: store))
    }

    /// Whether a declaration's base name is something an identifier token could ever equal.
    ///
    /// Asked of every name that enters a walk's frontier, at every hop, not only of the seed set. The two paths carry the same kind of thing (a declaration's base name) and pay the same price for an operator: a name the visitor can never match, whose substring pre-filter matches almost everything.
    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return first.isLetter || first == "_"
    }
}

extension AffectedNameSeed {
    /// The files a walk counts each name's sites in: only its seeds' own files where every seed carrying the name is private to its file, and every file otherwise.
    struct FileScope {
        private var files: [String: Set<String>] = [:]
        private var open: Set<String> = []

        /// Takes `seed` into the scope, `scanned` saying whether its name was already scanned; `true` where that scan was narrower than the name now allows, so the name has to be scanned again.
        @discardableResult
        mutating func admit(_ seed: AffectedNameSeed, scanned: Bool = false) -> Bool {
            guard !open.contains(seed.name) else { return false }
            guard let file = seed.file, files[seed.name] != nil || !scanned else {
                // A wider seed, or a name a scan already counted everywhere (a fallback's), is counted everywhere from now on.
                open.insert(seed.name)
                return files.removeValue(forKey: seed.name) != nil && scanned
            }
            return files[seed.name, default: []].insert(file).inserted && scanned
        }

        /// The scope of a walk's first seeds, before any scan.
        init(_ seeds: some Sequence<AffectedNameSeed> = []) {
            admit(contentsOf: seeds)
        }

        /// Takes seeds no scan has counted yet into the scope.
        mutating func admit(contentsOf seeds: some Sequence<AffectedNameSeed>) {
            for seed in seeds {
                admit(seed)
            }
        }

        /// Takes a seed reached on a later hop into the scope, and takes its module out of `seen` where the name was scanned more narrowly than it now counts, so the walk scans it again.
        mutating func admit(_ seed: AffectedNameSeed, reopening seen: inout [String: Set<String>]) {
            if admit(seed, scanned: seen[seed.name] != nil) {
                seen[seed.name]?.remove(seed.module)
            }
        }

        /// Whether a site of `name` in `path` can be a use of the name's seeds.
        func counts(_ name: String, in path: String) -> Bool {
            files[name]?.contains(path) ?? true
        }
    }
}
