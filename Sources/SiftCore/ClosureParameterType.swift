//
// Copyright © Agulhas Labs
//

import SwiftSyntax

/// Whether a written parameter type can take a closure literal, judged generously: only a type provably not a function type says no.
///
/// A bare name rules a closure out only where the caller vouches that it means the standard type, through `standardNames`: the index declares nothing of that name and no enclosing generic clause does. Sugar, tuples and a `Swift.` or `Foundation.` member type rule one out unvouched.
struct ClosureParameterType {
    /// The standard-library and Foundation nominals that are never function types.
    static let closedNames: Set<String> = [
        "String", "Substring", "Character", "Bool", "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float",
        "Array", "Dictionary", "Set", "Range", "ClosedRange", "Data", "URL", "Date", "UUID",
    ]

    /// Whether a closure literal can be passed for a parameter written as `type`, where `generics` are the names its signature's own generic clause declares and `standardNames` the closed names the caller vouches mean the standard type.
    static func takesClosure(_ type: TypeSyntax, generics: Set<String>, standardNames: Set<String> = []) -> Bool {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return takesClosure(attributed.baseType, generics: generics, standardNames: standardNames)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return takesClosure(optional.wrappedType, generics: generics, standardNames: standardNames)
        }
        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return takesClosure(optional.wrappedType, generics: generics, standardNames: standardNames)
        }
        if type.is(ArrayTypeSyntax.self) || type.is(DictionaryTypeSyntax.self) {
            return false
        }
        if let tuple = type.as(TupleTypeSyntax.self) {
            guard tuple.elements.count > 1 else {
                return tuple.elements.first.map { takesClosure($0.type, generics: generics, standardNames: standardNames) } ?? true
            }
            return false
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return takesClosure(identifier: identifier.name.text, arguments: identifier.genericArgumentClause, generics: generics, standardNames: standardNames)
        }
        if let member = type.as(MemberTypeSyntax.self) {
            guard let base = member.baseType.as(IdentifierTypeSyntax.self)?.name.text, base == "Swift" || base == "Foundation" else { return true }
            if member.name.text == "Optional" {
                return takesClosure(optionalArguments: member.genericArgumentClause, generics: generics, standardNames: standardNames)
            }
            return !closedNames.contains(member.name.text)
        }
        return true
    }

    /// Whether the property the first of `bindings` declares can take a closure, read from its own annotation, else its initial value's, else the annotation of the next binding that has one, as `var a, b: Int` types both.
    static func takesClosure(bindings: [PatternBindingSyntax], standardNames: Set<String> = []) -> Bool {
        for binding in bindings {
            if let annotation = binding.typeAnnotation {
                return takesClosure(annotation.type, generics: [], standardNames: standardNames)
            }
            if binding.initializer != nil {
                return true
            }
        }
        return true
    }

    /// The names a function's or an initializer's own generic clause declares, found from its parameter `list`.
    static func generics(enclosing list: FunctionParameterListSyntax) -> Set<String> {
        var node = list.parent
        while let current = node {
            if let function = current.as(FunctionDeclSyntax.self) {
                return names(in: function.genericParameterClause)
            }
            if let initializer = current.as(InitializerDeclSyntax.self) {
                return names(in: initializer.genericParameterClause)
            }
            node = current.parent
        }
        return []
    }

    private static func names(in clause: GenericParameterClauseSyntax?) -> Set<String> {
        Set(clause?.parameters.map(\.name.text) ?? [])
    }

    private static func takesClosure(identifier name: String, arguments: GenericArgumentClauseSyntax?, generics: Set<String>, standardNames: Set<String>) -> Bool {
        if name == "Optional" {
            return takesClosure(optionalArguments: arguments, generics: generics, standardNames: standardNames)
        }
        return generics.contains(name) || !standardNames.contains(name)
    }

    private static func takesClosure(optionalArguments arguments: GenericArgumentClauseSyntax?, generics: Set<String>, standardNames: Set<String>) -> Bool {
        guard let first = arguments?.arguments.first, case let .type(wrapped) = first.argument else { return true }
        return takesClosure(wrapped, generics: generics, standardNames: standardNames)
    }
}

extension ClosureParameterType {
    /// The closed names that, for the declaration `row`, provably mean the standard type, or none where any step cannot be read.
    ///
    /// A name the index declares as any symbol is out, and so is every generic parameter of a type the row sits in, or of the type an extension of one extends; `declared` is the closed names the index declares, where the caller has read them once for many rows.
    static func standardNames(for row: SymbolRow, in index: IndexStore, declared: Set<String>? = nil) throws -> Set<String> {
        let taken = try declared ?? declaredClosedNames(in: index)
        guard let generics = try enclosingGenerics(of: row, in: index) else { return [] }
        return closedNames.subtracting(taken).subtracting(generics)
    }

    /// The closed names the index declares as any symbol at all.
    static func declaredClosedNames(in index: IndexStore) throws -> Set<String> {
        try closedNames.filter { try !index.symbols(named: $0).isEmpty }
    }

    /// The generic parameter names of the types `row` sits in, or `nil` where a signature or an extended type cannot be read.
    private static func enclosingGenerics(of row: SymbolRow, in index: IndexStore) throws -> Set<String>? {
        var names: Set<String> = []
        var pending = [row]
        var visited: Set<Int64> = []
        while let current = pending.popLast() {
            guard let parentID = current.parentID, visited.insert(parentID).inserted else { continue }
            guard let parent = try index.symbol(withID: parentID) else { return nil }
            let types = parent.kind == .extensionKind ? try index.symbols(named: extendedName(of: parent)).filter(isNominalType) : [parent]
            guard !types.isEmpty, types.allSatisfy(isNominalType) else { return nil }
            for type in types {
                guard let declared = generics(of: type) else { return nil }
                names.formUnion(declared)
            }
            pending += types
        }
        return names
    }

    /// The simple name an extension's recorded name extends: its last component, without generic arguments.
    private static func extendedName(of extensionRow: SymbolRow) -> String {
        let last = extensionRow.name.split(separator: ".").last.map(String.init) ?? extensionRow.name
        return String(last.prefix { $0 != "<" })
    }

    /// The generic parameters, and a protocol's primary associated types, that the nominal declaration `row` writes, or `nil` where its signature does not parse back to one.
    private static func generics(of row: SymbolRow) -> Set<String>? {
        NestingGate.parseOrEmpty(row.signature) { tree -> Set<String>? in
            guard let item = tree.statements.first?.item else { return nil }
            if let declaration = item.as(StructDeclSyntax.self) {
                return names(in: declaration.genericParameterClause)
            }
            if let declaration = item.as(ClassDeclSyntax.self) {
                return names(in: declaration.genericParameterClause)
            }
            if let declaration = item.as(EnumDeclSyntax.self) {
                return names(in: declaration.genericParameterClause)
            }
            if let declaration = item.as(ActorDeclSyntax.self) {
                return names(in: declaration.genericParameterClause)
            }
            if let declaration = item.as(ProtocolDeclSyntax.self) {
                return Set(declaration.primaryAssociatedTypeClause?.primaryAssociatedTypes.map(\.name.text) ?? [])
            }
            return nil
        }
    }

    private static func isNominalType(_ row: SymbolRow) -> Bool {
        [.structKind, .classKind, .enumKind, .actor, .protocolKind].contains(row.kind)
    }
}
