//
// Copyright © Agulhas Labs
//

/// What `digest` answers for a target on a type the repository writes and declares nowhere, a path or package dependency's, where none of the repository's extensions serves it.
///
/// SwiftSure indexes no dependency sources, so a member the repository's extensions do not declare is neither confirmed nor ruled out: the answer says so, and lists what the repository can answer, its extensions of the type, its own declarations of the member's name on other types, and the `where` query for its uses. Every such answer is a miss, since it serves no source.
struct DigestExternalTypeAnswer {
    let renderer: DigestRenderer

    /// The answer for `name` under `qualifiers`, or `nil` where the type the path names is not external by ``ExternalTypeTest``.
    ///
    /// The type is the path's last qualifier, so `Dep.Tally.count` asks about `Tally`; with no qualifier the type is `name` itself. An extension is the type's only where the shorter of its written path and the asked one ends the other: `extension Tally` or `extension Dep.Tally` for `Dep.Tally`, never `extension Other.Tally`; any of them for a bare `Tally`, which names no parent. `pointer` gives the cross-root pointer the answer ends with.
    func answer(name: String, qualifiers: [String], options: DigestOptions, pointer: () -> [String]) throws -> MeasuredAnswer? {
        let type = qualifiers.last ?? name
        let written = try ExtensionPaths.written(endingIn: type, in: renderer.store)
        let typePath = qualifiers.isEmpty ? [name] : qualifiers
        let extensions = written.filter { extended in
            let path = extended.path.split(separator: ".").map(String.init)
            let shared = min(path.count, typePath.count)
            return typePath.suffix(shared) == path.suffix(shared)
        }.map(\.row)
        // The type asked for itself, extended at any path, is answered with its extensions before a miss gets here.
        if qualifiers.isEmpty, !written.isEmpty {
            return nil
        }
        guard try isExternal(type, extensions: extensions) else { return nil }
        var lines = try renderer.absenceBanner()
        guard !qualifiers.isEmpty else {
            lines.append("\(type)\(DigestMiss.declaredOutsideLead)\(DigestMiss.noLocalExtensionsSuffix)")
            return MeasuredAnswer(text: (lines + pointer()).joined(separator: "\n"), missed: true)
        }
        if qualifiers.count > 1, let body = try memberBody(name, type: type, declaredIn: extensions, options: options) {
            return MeasuredAnswer(text: body)
        }
        let base = QualifiedPath.baseName(of: name)
        lines.append("\(type)\(DigestMiss.declaredOutsideLead), so \(base)\(DigestMiss.unconfirmedMemberSuffix)")
        lines.append("")
        if extensions.isEmpty {
            lines.append("no extension of \(type) in this repository")
        } else {
            lines.append("extensions of \(type) (\(extensions.count)) — digest \(type) serves their members:")
            lines += extensions.prefix(DigestCaps.listCap).map { "  extension \($0.name)\(extensionContext($0)) — \($0.module) — \($0.path)\($0.rangeDescription)" }
            if extensions.count > DigestCaps.listCap {
                lines.append("  truncated: \(extensions.count - DigestCaps.listCap) more extensions")
            }
        }
        let elsewhere = try renderer.store.symbols(named: base).filter { $0.kind != .extensionKind }
        if !elsewhere.isEmpty {
            lines += ["", "other declarations of \(base) in this repository (\(elsewhere.count)):"]
            for row in elsewhere.prefix(DigestCaps.listCap) {
                try lines.append("  \(renderer.qualifiedTarget(of: row)) — \(row.kind.rawValue) — \(row.path)\(row.rangeDescription)")
            }
            if elsewhere.count > DigestCaps.listCap {
                lines.append("  truncated: \(elsewhere.count - DigestCaps.listCap) more declarations")
            }
        }
        lines += ["", "where --refs \(type).\(base) lists this repository's uses of it"]
        return MeasuredAnswer(text: (lines + pointer()).joined(separator: "\n"), missed: true)
    }

    /// The source of the member `name` declared in one of `extensions`, or `nil` where none declares it: a longer path than `Tally.count` reaches the extension `extension Tally` only through the type's own name, which other extensions of a `Tally` answer to as well.
    private func memberBody(_ name: String, type: String, declaredIn extensions: [SymbolRow], options: DigestOptions) throws -> String? {
        let target = "\(type).\(name)"
        let owners = Set(extensions.map(\.id))
        let members = try WhereRenderer(store: renderer.store).declarations(for: target).filter { row in
            !row.kind.isContainer && row.parentID.map(owners.contains) == true
        }
        return members.isEmpty ? nil : try renderer.memberBody(of: members, target: target, options: options)
    }

    /// Whether `type` is declared outside the repository, the working tree's type uses scanned only where the index holds neither a declaration nor an extension of it, and only until a batch of them writes the type.
    private func isExternal(_ type: String, extensions: [SymbolRow]) throws -> Bool {
        let test = ExternalTypeTest(store: renderer.store)
        guard try test.indexDeclaresNothing(named: type) else { return false }
        if !extensions.isEmpty {
            return true
        }
        guard let typeUsesSettle = renderer.typeUsesSettle else { return false }
        return try typeUsesSettle(type) { try test.writesTheType(type, at: $0) }
    }
}
