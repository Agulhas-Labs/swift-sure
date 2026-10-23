//
// Copyright © Agulhas Labs
//

import Foundation

/// The widest level at which another declaration exposes one: names it in its head — its signature, inheritance clause, generic constraint or a default argument — or in an `@inlinable` body, so narrowing it below that level is a compile error.
///
/// The exposure, not the spelling, decides: outside code reaches a type through `kit.make()` without ever writing its name.
final class AccessExposure {
    private let store: IndexStore
    private let repoRoot: URL
    private let uncoveredFiles: Set<String>
    private var inlinable: [Inlined]?
    private var frozen: [Inlined]?
    private var defaults: [Int64: String] = [:]

    /// `uncoveredFiles` are the repository-relative paths of the Swift files the index store does not answer for as they stand, empty where no store resolves uses.
    init(store: IndexStore, repoRoot: URL, uncoveredFiles: Set<String> = []) {
        self.store = store
        self.repoRoot = repoRoot
        self.uncoveredFiles = uncoveredFiles
    }

    /// An `@inlinable` or `@usableFromInline` declaration exposes at `public` whatever its own level, since what it names must be public or `@usableFromInline`; a declaration inside a type subject — in its body, a nested type or an extension of it — never exposes it, since narrowing the type caps that declaration too.
    ///
    /// A `@frozen` type's stored instance property exposes at `public` what its type annotation and initial value name, whatever the property's own level, since they are fixed in the type's layout; the `@frozen` type itself goes no lower than `package`, the narrowest level the attribute allows. An extension's `where` clause, a constrained conformance's included, exposes what it names at the level of the extension's widest member, or its own written level, since its members are visible no wider than its requirements.
    ///
    /// `references` are the index store's references to the subject, where it resolves its uses, and `nil` where they are name-matched: each one inside an `@inlinable` declaration, a `@frozen` type's stored instance property or a parameter's default value exposes it however it is spelled, and an implicit-member `init(` call in such code of an initializer's module exposes every initializer of that module where the store has no reference to tell which it builds: everywhere without them, and with them in the files the store does not cover.
    func level(exposing subject: AccessSubject, references: [Reference]?) throws -> AccessLevel? {
        let target = try target(of: subject)
        var widest: AccessLevel? = subject.kind.isTypeDeclaration && Self.names("@frozen", in: subject.signature) ? .packageLevel : nil
        var seen: Set<Int64> = []
        for searched in target.searched {
            for row in try store.symbols(signatureContaining: searched) where row.kind != .extensionKind && seen.insert(row.id).inserted {
                let head = target.isInitializer ? defaultedParameters(of: row) : row.signature
                guard !(row.path == subject.path && row.line == subject.line), target.mayName(head, inHead: true) else { continue }
                let home = try home(of: row)
                guard !target.contains(home), target.names(in: head, at: home) else { continue }
                widest = try max(widest ?? .privateLevel, Self.isFragile(row.signature) ? .publicLevel : cappedLevel(of: row))
            }
        }
        for entry in try inlinableBodies() + frozenStoredProperties() where !(entry.path == subject.path && entry.line == subject.line) && !target.contains(entry.home) {
            guard target.mayName(entry.body, inHead: false), target.names(in: entry.body, at: entry.home) else { continue }
            widest = .publicLevel
        }
        if let references {
            widest = try [widest, level(needing: references, of: subject, target: target)].compactMap(\.self).max()
        }
        if target.isInitializer, references == nil || !uncoveredFiles.isEmpty {
            widest = try [widest, levelOfImplicitInitializers(for: subject, target: target, in: references == nil ? nil : uncoveredFiles)].compactMap(\.self).max()
        }
        return try [widest, requirementLevel(exposing: target)].compactMap(\.self).max()
    }

    /// Whether `text` holds `name` as a whole identifier.
    static func names(_ name: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let found = text.range(of: name, range: searchStart ..< text.endIndex) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !isIdentifier(before), !isIdentifier(after) {
                return true
            }
            searchStart = found.upperBound
        }
        return false
    }

    /// Whether `text` calls an initializer by implicit member: an `init(` after a dot with no type, value or `self` before it.
    static func callsImplicitInit(_ text: String) -> Bool {
        var searchStart = text.startIndex
        while let found = text.range(of: "init(", range: searchStart ..< text.endIndex) {
            searchStart = found.upperBound
            guard found.lowerBound > text.startIndex, text[text.index(before: found.lowerBound)] == "." else { continue }
            let before = text[..<text.index(before: found.lowerBound)].last { !$0.isWhitespace }
            if !(before.map { isIdentifier($0) || ")]>?!`".contains($0) } ?? false) {
                return true
            }
        }
        return false
    }
}

extension AccessExposure {
    /// One `@inlinable` declaration or `@frozen` type's stored property: where it is, the type it sits in, and its whole lines.
    struct Inlined {
        let path: String
        let line: Int
        let endLine: Int
        let home: Home
        let body: String
    }

    /// One reference the index store records to a subject: its file, relative to the repository, and its line and UTF-8 column, both counted from 1.
    struct Reference {
        let path: String
        let line: Int
        let column: Int
    }

    /// Where a declaration sits: its module and the dotted path of the type it is declared in or an extension of, empty at top level.
    struct Home: Equatable {
        let module: String
        let typePath: String
    }

    /// What one subject's exposure is matched on.
    struct Target {
        /// The name a declaration exposing it spells: an initializer's type's, since it is called through its type.
        let name: String
        let isInitializer: Bool
        /// The subject's own place in the index, `nil` where the index does not hold it.
        let home: Home?
        /// The dotted path of the type a type subject declares, `nil` for any other subject.
        let ownTypePath: String?

        /// The texts the index is searched for: an initializer is also called through `Self` or a bare `init` in its own type's members.
        var searched: [String] {
            isInitializer && home != nil ? [name, "Self", "init"] : [name]
        }

        /// Whether a declaration at `other` sits inside the type subject, so narrowing the subject caps it too.
        func contains(_ other: Home) -> Bool {
            guard let ownTypePath, other.module == home?.module else { return false }
            return other.typePath == ownTypePath || other.typePath.hasPrefix(ownTypePath + ".")
        }

        /// The text-only half of `names(in:at:)`, checked before the index is asked where the text sits: an initializer's head is passed as its defaulted parameters alone, the one place a head calls it, and `Self` or `init` counts there or past a body's first `{`, so another initializer's own head never names it.
        func mayName(_ text: String, inHead: Bool) -> Bool {
            guard isInitializer else { return AccessExposure.names(name, in: text) }
            guard let start = inHead ? text.startIndex : text.firstIndex(of: "{") else { return AccessExposure.names(name, in: text) }
            let rest = String(text[start...])
            return AccessExposure.names(name, in: text) || AccessExposure.names("Self", in: rest) || AccessExposure.names("init", in: rest)
        }

        /// Whether `text`, written at `other`, names the subject: by its name, or for an initializer by `Self` or `init` in its own type's members.
        func names(in text: String, at other: Home) -> Bool {
            if AccessExposure.names(name, in: text) {
                return true
            }
            return isInitializer && other == home
        }
    }
}

private extension AccessExposure {
    static func isIdentifier(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }

    /// Whether a declaration's head marks it `@inlinable` or `@usableFromInline`.
    static func isFragile(_ signature: String) -> Bool {
        names("@inlinable", in: signature) || names("@usableFromInline", in: signature)
    }

    /// A declaration's level capped by every type enclosing it.
    func cappedLevel(of row: SymbolRow) throws -> AccessLevel {
        try store.parentChain(of: row).filter(\.kind.isTypeDeclaration).map(\.accessLevel).reduce(row.accessLevel, min)
    }

    /// Where a stored declaration sits: an extension's extended type, then each type nested in it.
    func home(of row: SymbolRow) throws -> Home {
        let typePath = try store.parentChain(of: row).reduce(into: "") { path, parent in
            if parent.kind == .extensionKind {
                path = DeclaredTypeName.path(ofSpelling: parent.name)
            } else if parent.kind.isTypeDeclaration {
                path = path.isEmpty ? parent.name : "\(path).\(parent.name)"
            }
        }
        return Home(module: row.module, typePath: typePath)
    }

    /// What `subject` is matched on, read from its own row in the index.
    func target(of subject: AccessSubject) throws -> Target {
        let own = try store.symbols(inFile: subject.path).first { $0.line == subject.line && $0.kind == subject.kind && $0.name == subject.name }
        let home = try own.map(home(of:))
        let isInitializer = subject.kind == .initializer
        let ownTypePath = subject.kind.isTypeDeclaration ? home.map { $0.typePath.isEmpty ? subject.name : "\($0.typePath).\(subject.name)" } : nil
        return Target(
            name: isInitializer ? subject.containerName ?? subject.name : CallSiteScanner.baseName(of: subject.name),
            isInitializer: isInitializer,
            home: home,
            ownTypePath: ownTypePath
        )
    }

    /// The level the store's references to the subject need where they sit: `public` inside an `@inlinable` declaration or a `@frozen` type's stored instance property, and inside a parameter's default value the level of the declaration it heads, `public` where that is fragile.
    func level(needing references: [Reference], of subject: AccessSubject, target: Target) throws -> AccessLevel? {
        let inlined = try (inlinableBodies() + frozenStoredProperties()).filter { !($0.path == subject.path && $0.line == subject.line) && !target.contains($0.home) }
        if references.contains(where: { reference in inlined.contains { $0.path == reference.path && ($0.line ... $0.endLine).contains(reference.line) } }) {
            return .publicLevel
        }
        var widest: AccessLevel?
        for (path, inFile) in Dictionary(grouping: references, by: \.path) {
            var lines: [Substring]?
            for row in try store.symbols(inFile: path) where !(row.path == subject.path && row.line == subject.line) && !defaultedParameters(of: row).isEmpty {
                let held = inFile.filter { (row.line ... max(row.line, row.endLine)).contains($0.line) }
                guard !held.isEmpty, try !target.contains(home(of: row)) else { continue }
                let source = lines ?? ((try? String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false)
                lines = source
                guard row.line >= 1, row.line <= source.count else { continue }
                let own = ParameterDefaults(source: source[(row.line - 1) ..< min(row.endLine, source.count)].joined(separator: "\n"))
                guard held.contains(where: { own.holdsDefault(line: $0.line - row.line + 1, column: $0.column) }) else { continue }
                widest = try max(widest ?? .privateLevel, Self.isFragile(row.signature) ? .publicLevel : cappedLevel(of: row))
            }
        }
        return widest
    }

    /// The level an implicit-member `init(` call in an initializer's own module needs where no store reference resolves it, in `files` or in every file where that is `nil`: which type it builds cannot be told without types, so it counts for every initializer of the module, at `public` in an `@inlinable` body or a `@frozen` type's stored instance property and at the declaration's level in a parameter's default value.
    func levelOfImplicitInitializers(for subject: AccessSubject, target: Target, in files: Set<String>?) throws -> AccessLevel? {
        let scanned = { (module: String, path: String) in (target.home.map { $0.module == module } ?? true) && (files?.contains(path) ?? true) }
        let isOwn = { (path: String, line: Int) in path == subject.path && line == subject.line }
        if try (inlinableBodies() + frozenStoredProperties()).contains(where: { scanned($0.home.module, $0.path) && !isOwn($0.path, $0.line) && Self.callsImplicitInit($0.body) }) {
            return .publicLevel
        }
        var widest: AccessLevel?
        for row in try store.symbols(signatureContaining: "init(") where scanned(row.module, row.path) && !isOwn(row.path, row.line) && Self.callsImplicitInit(defaultedParameters(of: row)) {
            widest = try max(widest ?? .privateLevel, Self.isFragile(row.signature) ? .publicLevel : cappedLevel(of: row))
        }
        return widest
    }

    /// The parameters a declaration's head gives a default value, type and value together, read once per answer.
    func defaultedParameters(of row: SymbolRow) -> String {
        if let known = defaults[row.id] {
            return known
        }
        let text = ParameterDefaults(source: row.signature).text
        defaults[row.id] = text
        return text
    }

    /// Every `@inlinable` declaration's place and whole lines, read once per answer.
    func inlinableBodies() throws -> [Inlined] {
        if let inlinable {
            return inlinable
        }
        let found = try wholeLines(of: store.symbols(signatureContaining: "@inlinable"))
        inlinable = found
        return found
    }

    /// Every stored instance property of a `@frozen` type, as its place and whole lines, read once per answer: a property observing its value with `willSet` or `didSet` is stored too.
    func frozenStoredProperties() throws -> [Inlined] {
        if let frozen {
            return frozen
        }
        var rows: [SymbolRow] = []
        for type in try store.symbols(signatureContaining: "@frozen") where type.kind.isTypeDeclaration && Self.names("@frozen", in: type.signature) {
            rows += try store.children(of: type.id).filter { $0.kind == .variable && $0.isStored && !$0.isStatic }
        }
        let found = try wholeLines(of: rows)
        frozen = found
        return found
    }

    /// Each declaration's place and whole lines, each file read once.
    func wholeLines(of rows: [SymbolRow]) throws -> [Inlined] {
        var files: [String: [Substring]] = [:]
        var found: [Inlined] = []
        for row in rows {
            if files[row.path] == nil {
                let source = (try? String(contentsOf: repoRoot.appending(path: row.path), encoding: .utf8)) ?? ""
                files[row.path] = source.split(separator: "\n", omittingEmptySubsequences: false)
            }
            let lines = files[row.path] ?? []
            guard row.line >= 1, row.line <= lines.count else { continue }
            let body = lines[(row.line - 1) ..< min(row.endLine, lines.count)].joined(separator: "\n")
            try found.append(Inlined(path: row.path, line: row.line, endLine: row.endLine, home: home(of: row), body: body))
        }
        return found
    }

    /// The widest level at which an extension other than one of the subject's own requires it: its members' widest, capped by their enclosing types, or the extension's own written level; `nil` for an initializer, which no requirement names.
    func requirementLevel(exposing target: Target) throws -> AccessLevel? {
        guard !target.isInitializer else { return nil }
        var widest: AccessLevel?
        for row in try store.symbols(signatureContaining: target.name) where row.kind == .extensionKind {
            let extended = Home(module: row.module, typePath: DeclaredTypeName.path(ofSpelling: row.name))
            guard !target.contains(extended), Self.names(target.name, in: Self.whereClause(of: row)) else { continue }
            let written = AttributeScanner.strippingLeadingAttributes(row.signature).split(separator: " ").prefix(2).compactMap { AccessLevel(rawValue: String($0)) }
            let levels = try written + store.children(of: row.id).map(cappedLevel(of:))
            if let level = levels.max() {
                widest = max(widest ?? level, level)
            }
        }
        return widest
    }

    /// An extension's `where` clause as written, empty where it has none: the conformances it adds and its extended type's generic arguments are no requirement its members need visible.
    static func whereClause(of row: SymbolRow) -> String {
        row.signature.range(of: #"\bwhere\b"#, options: .regularExpression).map { String(row.signature[$0.lowerBound...]) } ?? ""
    }
}
