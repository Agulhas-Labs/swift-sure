//
// Copyright © Agulhas Labs
//

/// `where Dep.member` for a `Dep` the repository writes and declares nowhere: a path or package dependency's type, whose sources the index never holds.
///
/// The index can neither confirm nor deny the member, so the answer says the type is declared outside the repository, in the words `digest` uses, and then lists what the repository can answer: its extensions of the type, its own declarations of the member's name on other types, and its own uses of the member. With a fresh store those uses are resolved references to the dependency's symbol; without one, or with one the tree has moved past, they are name matches, marked `by written name`, among which a same-named member of another type may appear.
struct WhereExternalType {
    /// The renderer whose index, scan by written name and store sections the answer is made from.
    let renderer: WhereRenderer
    /// The repository's declarations of the member's name, none of them under the type.
    let elsewhere: [SymbolRow]
    /// Whether the repository holds a file the parser could not finish, which may hold the type's declaration: the headline then says the type is declared in no file the index read in full rather than that it is declared outside the repository.
    let parseErrorsElsewhere: Bool

    /// The answer for a member written on a type the repository writes and declares nowhere, or `nil` where the type is declared here, written nowhere, or the query names no qualifier.
    func answer(
        member: String,
        on qualifiers: [String],
        semantic: SemanticInput,
        options: WhereOptions,
        paging: SyntacticSweepPaging,
        storePointer: [String]
    ) async throws -> Answer? {
        guard let type = qualifiers.last else { return nil }
        let extensions = try ExtensionPaths.extensions(ofTypeNamed: type, in: renderer.store)
        guard try await isDeclaredOutside(type, extensions: extensions) else { return nil }
        let base = QualifiedPath.baseName(of: member)
        var lines = [parseErrorsElsewhere
            ? "\(type) is declared in no file the index read in full — outside this repository, or in a file that did not fully parse — so \(base) is neither confirmed nor ruled out on it"
            : "\(type) is declared outside this repository — its sources are not indexed, so \(base) is neither confirmed nor ruled out on it"]
        if !extensions.isEmpty {
            try renderer.filesCollector?.recordDeclarations(extensions, qualifiedName: renderer.qualifiedName(of:))
            lines += ["", "extensions of \(type) (\(extensions.count)):"]
            lines += extensions.prefix(WhereRenderer.listCap).map { "  extension \($0.name) — \($0.module) — \($0.path)\($0.rangeDescription)" }
            if extensions.count > WhereRenderer.listCap {
                lines.append("  truncated: \(extensions.count - WhereRenderer.listCap) more extensions")
            }
        }
        if !elsewhere.isEmpty {
            lines += ["", "other declarations of \(base) in this repository (\(elsewhere.count)):"]
            for row in elsewhere.prefix(WhereRenderer.listCap) {
                try lines.append("  \(renderer.qualifiedName(of: row)) — \(row.kind.rawValue) — \(row.path)\(row.rangeDescription)")
            }
            if elsewhere.count > WhereRenderer.listCap {
                lines.append("  truncated: \(elsewhere.count - WhereRenderer.listCap) more declarations")
            }
        }
        if options.declarationsOnly {
            return Answer(lines: lines, axis: nil)
        }
        let sites = await (renderer.callSites?([base: .use])[base] ?? []).sorted { ($0.path, $0.line) < ($1.path, $1.line) }
        guard case let .active(context) = semantic else {
            return Answer(lines: lines + writtenNameUses(of: base, sites: sites, options: options, paging: paging) + storePointer, axis: nil)
        }
        let occurrences = OccurrenceFreshness(store: renderer.store, context: context, projectDirectories: renderer.projectDirectories)
        let references = resolvedReferences(to: member, base: base, on: type, context: context)
        // Every file the answer could cite is judged before either list is chosen: a store the tree has moved past answers by written name, as with no store.
        for hit in references ?? [] {
            _ = occurrences.kind(of: hit.path)
        }
        for site in sites {
            _ = occurrences.kind(ofFile: site.path)
        }
        let verdict = SemanticAxis.of(refusals: [], occurrences: occurrences)
        if case .stale = verdict {
            return Answer(lines: lines + writtenNameUses(of: base, sites: sites, options: options, paging: paging), axis: verdict)
        }
        guard let references else {
            // The store records no member of the name on the type: the dependency is unbuilt, or has no such member, so the uses are name matches and the header says the store found nothing to resolve.
            return Answer(lines: lines + writtenNameUses(of: base, sites: sites, options: options, paging: paging), axis: .unresolved(symbols: 1))
        }
        // The store records nothing in a file it holds no unit for, an unbuilt test target above all, so the lines there writing the name are listed below the references, and the header counts those files and the targets not built, as any `where --refs` answer does.
        let names: ScannedNames = [base]
        let coverage = try context.testFileCoverage(in: renderer.store)
        var unbuilt: [String] = []
        if coverage.withoutUnit > 0 {
            let classified = try context.testFilesWithoutUnit(in: renderer.store, projectDirectories: renderer.projectDirectories)
            unbuilt = classified.unbuilt + classified.outsideTargets
        }
        let mentions = try WhereChangedFileMentions(names: names, unbuilt: unbuilt, refused: [], in: renderer.store, context: context, judge: occurrences, listsEveryLine: options.includeReferences, readsStoredFiles: false, offset: options.offset)
        if let collector = renderer.filesCollector {
            mentions.record(into: collector)
        }
        let axis = try SemanticAxis.of(
            refusals: [],
            occurrences: [occurrences],
            testFilesWithoutUnit: coverage.partialCount,
            targetsNotBuilt: TargetsNotBuilt(writing: names, in: renderer.store, context: context, projectDirectories: renderer.projectDirectories),
            listedByName: mentions.listedFiles
        )
        guard !references.isEmpty else {
            let listed = mentions.placed(in: [])
            return Answer(lines: lines + (listed.isEmpty ? ["", "no reference to \(type).\(base) in this repository"] : listed), axis: axis)
        }
        let section = renderer.referenceSection(for: "\(type).\(base)", hits: references, offset: options.offset, context: context, occurrences: occurrences, paging: paging)
        return Answer(lines: lines + mentions.placed(in: section), axis: axis)
    }

    /// Whether `type` is one the repository writes and declares nowhere, by ``ExternalTypeTest``, the working tree scanned only where the index finds no extension of it.
    private func isDeclaredOutside(_ type: String, extensions: [SymbolRow]) async throws -> Bool {
        let test = ExternalTypeTest(store: renderer.store)
        guard try test.indexDeclaresNothing(named: type) else { return false }
        if !extensions.isEmpty {
            return true
        }
        guard let callSites = renderer.callSites else { return false }
        return try await test.writesTheType(type, at: callSites([type: .typeUse])[type] ?? [])
    }

    /// The store's references to the members named `member` that it records as children of a type named `type`, or `nil` where it records no such member.
    ///
    /// A function is named in its labeled form, so a member written with no labels is looked for as `base()` too. Only the repository's own files are kept: the dependency's sources are not this repository's uses.
    private func resolvedReferences(to member: String, base: String, on type: String, context: SemanticContext) -> [SemanticStore.Hit]? {
        let spellings = member.contains("(") ? [member] : [member, base + "()"]
        let usrs = spellings.reduce(into: Set<String>()) { $0.formUnion(context.store.usrs(ofMembersNamed: $1, childOf: type)) }
        guard !usrs.isEmpty else { return nil }
        return usrs.sorted().flatMap { context.store.references(ofUSR: $0) }.filter { hit in
            (try? renderer.store.fileRow(path: context.relativePath(hit.path))) != nil
        }
    }

    /// The repository's uses of `.base`, matched by written name as `sites`, with the count line every no-store list opens with.
    private func writtenNameUses(of base: String, sites: [SyntacticCallSite], options: WhereOptions, paging: SyntacticSweepPaging) -> [String] {
        guard !sites.isEmpty else {
            return ["", "no use spelled \"\(base)\" anywhere in the working tree"]
        }
        let files = Set(sites.map(\.path)).count
        var lines = ["", "\"\(base)\" (\(sites.count) use\(sites.count == 1 ? "" : "s") by written name in \(files) file\(files == 1 ? "" : "s"); a same-named member of another type may be among them):"]
        renderer.filesCollector?.recordSites(sites)
        let detail: (SyntacticCallSite) -> String = { "in \($0.enclosing)" }
        if options.includeReferences {
            return lines + paging.rows(of: sites, detail: detail)
        }
        let cap = options.nameMatchedSiteCap ?? WhereRenderer.callSiteCap
        lines += NameMatchedSites.rows(sites.prefix(cap), detail: detail)
        if sites.count > cap {
            lines.append("    truncated: \(sites.count - cap) more uses")
        }
        return lines
    }
}

extension WhereExternalType {
    /// The lines of the answer, and the `semantic:` verdict that heads them where a store was open.
    struct Answer {
        let lines: [String]
        /// `nil` where no store was open, so the header keeps what the store's state already gave it.
        let axis: SemanticAxis?
    }
}
