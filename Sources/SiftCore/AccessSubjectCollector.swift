//
// Copyright © Agulhas Labs
//

/// Picks the declarations one file's changes put at `open`, `public` or `package` out of its after side, for `diff`'s access section.
///
/// A wholly added container is one change, so its members are read from the after side's parse; a protocol requirement, an enum case and an associated type are never subjects of their own, since their container's uses decide them.
struct AccessSubjectCollector {
    static let judgedLevels: Set<AccessLevel> = [.openLevel, .publicLevel, .packageLevel]

    static func subjects(in changes: [DeclarationChange], newSide: DiffFileSide?, path: String) -> [AccessSubject] {
        guard let symbols = newSide?.file.symbols else { return [] }
        var found: [AccessSubject] = []
        // In the declarations section's order, so the lookup budget is spent on the first declarations it lists.
        for change in DeclarationChange.listingOrder(changes) {
            guard let range = change.newRange else { continue }
            let widened = change.kind == .changed && change.oldAccess.flatMap { old in change.newAccess.map { old < $0 } } == true
            guard change.kind == .added || widened else { continue }
            guard let index = symbols.indices.first(where: { symbols[$0].line == range.line && symbols[$0].name == change.name && symbols[$0].kind == change.symbolKind }) else { continue }
            if let subject = subject(at: index, in: symbols, label: change.label, widened: widened, path: path) {
                found.append(subject)
            }
            if change.kind == .added, symbols[index].kind.isContainer {
                found += members(of: index, in: symbols, label: change.label, path: path)
            }
        }
        return found
    }

    /// The subjects with the exclusions their container's attributes decide wherever the index declares it, so a result builder's `build…` method or a property wrapper's `wrappedValue` in an extension in another file is not judged.
    static func excludingByContainer(_ subjects: [AccessSubject], in store: IndexStore) throws -> [AccessSubject] {
        var signatures: [String: [String]] = [:]
        return try subjects.map { subject in
            guard subject.exclusion == nil, let container = subject.containerName else { return subject }
            if signatures[container] == nil {
                signatures[container] = try store.typeDeclarations(named: container).map(\.signature)
            }
            let declared = signatures[container] ?? []
            guard !declared.isEmpty else { return subject }
            var read = subject
            let containerSignature = ([subject.containerSignature].compactMap(\.self) + declared).joined(separator: " ")
            read.exclusion = AccessExclusion.written(name: subject.name, kind: subject.kind, level: subject.level, signature: subject.signature, containerSignature: containerSignature)
            return read
        }
    }
}

private extension AccessSubjectCollector {
    static let ownerlessKinds: Set<SymbolKind> = [.extensionKind, .enumCase, .associatedType, .precedenceGroup]

    /// Every declaration nested under an added container, in source order, each labeled under the container's label.
    static func members(of parent: Int, in symbols: [ParsedSymbol], label: String, path: String) -> [AccessSubject] {
        var found: [AccessSubject] = []
        for index in symbols.indices where symbols[index].parentIndex == parent {
            let own = "\(label).\(symbols[index].name)"
            if let subject = subject(at: index, in: symbols, label: own, widened: false, path: path) {
                found.append(subject)
            }
            if symbols[index].kind.isContainer {
                found += members(of: index, in: symbols, label: own, path: path)
            }
        }
        return found
    }

    static func subject(at index: Int, in symbols: [ParsedSymbol], label: String, widened: Bool, path: String) -> AccessSubject? {
        let symbol = symbols[index]
        guard !ownerlessKinds.contains(symbol.kind) else { return nil }
        let parent = symbol.parentIndex.map { symbols[$0] }
        guard parent?.kind != .protocolKind else { return nil }
        var level = symbol.accessLevel
        var extended: [String] = []
        var ancestor = symbol.parentIndex
        while let current = ancestor {
            if symbols[current].kind == .extensionKind {
                let typeName = DeclaredTypeName.last(ofPath: symbols[current].name)
                if let declared = declaration(named: typeName, in: symbols) {
                    level = min(level, declared.accessLevel)
                } else {
                    extended.append(typeName)
                }
            } else if symbols[current].kind.isTypeDeclaration {
                level = min(level, symbols[current].accessLevel)
            }
            ancestor = symbols[current].parentIndex
        }
        guard judgedLevels.contains(level) else { return nil }
        let containerName = parent.map { $0.kind == .extensionKind ? DeclaredTypeName.last(ofPath: $0.name) : $0.name }
        let declaredContainer = parent?.kind == .extensionKind ? containerName.flatMap { declaration(named: $0, in: symbols) } : nil
        let containerSignature = [parent?.signature, declaredContainer?.signature].compactMap(\.self).joined(separator: " ")
        return AccessSubject(
            label: label,
            name: symbol.name,
            kind: symbol.kind,
            path: path,
            line: symbol.line,
            level: level,
            widened: widened,
            signature: symbol.signature,
            containerName: containerName,
            containerSignature: parent == nil ? nil : containerSignature,
            containerInherited: (parent?.inherited ?? []) + (declaredContainer?.inherited ?? []),
            extendedTypes: extended,
            exclusion: AccessExclusion.written(name: symbol.name, kind: symbol.kind, level: level, signature: symbol.signature, containerSignature: parent == nil ? nil : containerSignature)
        )
    }

    /// The type this file declares under `name`, which an extension of it is capped by.
    static func declaration(named name: String, in symbols: [ParsedSymbol]) -> ParsedSymbol? {
        symbols.first { $0.kind.isTypeDeclaration && $0.name == name }
    }
}
