//
// Copyright © Agulhas Labs
//

/// The line that ends a type digest, naming the members the compiler synthesizes for the type that the listing cannot show.
///
/// It names only what the type's declarations make possible: the inheritance clauses of the type and of every extension the digest lists for it say what it conforms to, and the members declared in them say what is written by hand and so not synthesized. A type with nothing left to name gets no line.
struct DigestSynthesizedNote {
    /// The raw types an enum's first inherited name can be for the compiler to synthesize `init(rawValue:)`.
    private static let rawTypes: Set<String> = [
        "String", "Character", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double", "CGFloat",
    ]

    /// The names the type conforms to, by last component, across its own inheritance clause and those of its extensions.
    let conformances: Set<String>
    /// The standard raw type an enum's first inherited name is, or nil when it is not one.
    let rawType: String?
    /// The members declared in the type's body, named with their labels.
    let bodyMembers: [SymbolRow]
    /// The members declared in the type's extensions, named with their labels.
    let extensionMembers: [SymbolRow]
    /// The kind of the type the note is for.
    let kind: SymbolKind

    /// The blank line and the note for `primary` with the extensions `extensions` listed under it, or nothing when the type has no synthesized member to name.
    static func lines(for primary: SymbolRow, extensions: [SymbolRow], store: IndexStore) throws -> [String] {
        let primaryEntries = try store.inheritedNames(of: primary.id)
        var names = Set<String>()
        for row in [primary] + extensions {
            let entries = row.id == primary.id ? primaryEntries : try store.inheritedNames(of: row.id)
            for entry in entries {
                names.formUnion(InheritedClause.components(of: entry).map { DeclaredTypeName.last(ofPath: $0) })
            }
        }
        let first = primaryEntries.first.flatMap { InheritedClause.components(of: $0).first }.map { DeclaredTypeName.last(ofPath: $0) }
        var inExtensions: [SymbolRow] = []
        for row in extensions {
            try inExtensions += store.children(of: row.id)
        }
        let note = try DigestSynthesizedNote(
            conformances: names,
            rawType: first.flatMap { rawTypes.contains($0) ? $0 : nil },
            bodyMembers: store.children(of: primary.id),
            extensionMembers: inExtensions,
            kind: primary.kind
        )
        let items = note.items
        return items.isEmpty ? [] : ["", "synthesized members (\(items.joined(separator: ", "))) not listed"]
    }

    private var items: [String] {
        guard kind == .structKind || kind == .enumKind || kind == .classKind else { return [] }
        var items: [String] = []
        let isValueType = kind != .classKind
        if kind == .structKind, !bodyMembers.contains(where: { $0.kind == .initializer }) {
            items.append("memberwise init")
        }
        if kind == .enumKind, rawType != nil, !declares(.initializer, "init(rawValue:)") {
            items.append("rawValue init")
        }
        if kind == .enumKind, conformances.contains("CaseIterable"), !hasAssociatedValues, !declares(.variable, "allCases") {
            items.append("allCases")
        }
        let codable = conformances.contains("Codable")
        let needsEncode = (codable || conformances.contains("Encodable")) && !declares(.function, "encode(to:)")
        let needsDecode = (codable || conformances.contains("Decodable")) && !declares(.initializer, "init(from:)")
        if needsEncode, needsDecode, codable || (conformances.contains("Encodable") && conformances.contains("Decodable")) {
            items.append("Codable")
        } else if needsEncode {
            items.append("encode(to:)")
        } else if needsDecode {
            items.append("init(from:)")
        }
        let hashable = conformances.contains("Hashable")
        if isValueType, hashable || conformances.contains("Equatable"), !declaresEquals {
            items.append("==")
        }
        if isValueType, hashable, !declares(.function, "hash(into:)") {
            items.append("hash(into:)")
        }
        return items
    }

    /// Whether a case of the enum carries associated values, which the store names with a parameter list (`value(_:)`), and the compiler synthesizes `allCases` only for an enum with none.
    ///
    /// A case cannot be declared in an extension, so the body is enough.
    private var hasAssociatedValues: Bool {
        bodyMembers.contains { $0.kind == .enumCase && $0.name.contains("(") }
    }

    private var declaresEquals: Bool {
        (bodyMembers + extensionMembers).contains { $0.kind == .function && $0.baseName == "==" }
    }

    private func declares(_ kind: SymbolKind, _ name: String) -> Bool {
        (bodyMembers + extensionMembers).contains { $0.kind == kind && $0.name == name }
    }
}
