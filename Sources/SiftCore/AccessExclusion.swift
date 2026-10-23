//
// Copyright © Agulhas Labs
//

/// Why `diff`'s access section does not judge a declaration: something reaches it that a scan of names cannot see, so it is counted on the `not judged` line instead of being called unused.
enum AccessExclusion: Int, Sendable, CaseIterable, Comparable {
    case witness
    case open
    case override
    case requiredInit
    case objc
    case inlinable
    case spi
    case dynamic
    case entryPoint
    case compiler
    case macro

    static func < (lhs: AccessExclusion, rhs: AccessExclusion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The `not judged` line's entry for `count` declarations of this kind.
    func label(_ count: Int) -> String {
        let one = count == 1
        return switch self {
        case .witness: "\(count) protocol \(one ? "witness" : "witnesses")"
        case .open: "\(count) open"
        case .override: "\(count) \(one ? "override" : "overrides")"
        case .requiredInit: "\(count) required \(one ? "init" : "inits")"
        case .objc: "\(count) @objc"
        case .inlinable: "\(count) @inlinable or @usableFromInline"
        case .spi: "\(count) @_spi"
        case .dynamic: "\(count) dynamic"
        case .entryPoint: "\(count) \(one ? "entry point" : "entry points")"
        case .compiler: "\(count) reached by the compiler, not by name"
        case .macro: "\(count) macro-generated, invisible to the parser"
        }
    }

    /// The exclusion the declaration's own head decides, before any lookup: its modifiers, its attributes, and the compiler-reached shapes; `nil` where only its uses can tell.
    static func written(name: String, kind: SymbolKind, level: AccessLevel, signature: String, containerSignature: String?) -> AccessExclusion? {
        let attributes = Set(AttributeScanner.attributeNames(in: signature))
        let containerAttributes = Set(containerSignature.map(AttributeScanner.attributeNames(in:)) ?? [])
        let words = AttributeScanner.strippingLeadingAttributes(signature).split(separator: " ")
        let modifiers = Set(words.prefix { !kindKeywords.contains($0) && !$0.hasPrefix("init") }.map(String.init))
        if level == .openLevel {
            return .open
        }
        if modifiers.contains("override") {
            return .override
        }
        if kind == .initializer, modifiers.contains("required") {
            return .requiredInit
        }
        if !attributes.isDisjoint(with: objcAttributes) || containerAttributes.contains("objcMembers") {
            return .objc
        }
        if attributes.contains("inlinable") || attributes.contains("usableFromInline") {
            return .inlinable
        }
        if attributes.contains("_spi") {
            return .spi
        }
        if modifiers.contains("dynamic") {
            return .dynamic
        }
        if !attributes.isDisjoint(with: ["main", "_cdecl", "_silgen_name"]) {
            return .entryPoint
        }
        return isReachedByCompiler(name: name, kind: kind, containerAttributes: containerAttributes) ? .compiler : nil
    }
}

private extension AccessExclusion {
    static let objcAttributes: Set<String> = ["objc", "objcMembers", "IBAction", "IBOutlet", "IBInspectable", "IBSegueAction", "NSManaged", "GKInspectable"]
    static let kindKeywords: Set<Substring> = ["func", "var", "let", "subscript", "struct", "class", "enum", "actor", "protocol", "typealias", "case", "macro", "operator"]

    /// Operators, subscripts, `callAsFunction`, a result builder's `build…` methods and a property wrapper's `wrappedValue` and `projectedValue`: their uses spell no name a scan finds.
    static func isReachedByCompiler(name: String, kind: SymbolKind, containerAttributes: Set<String>) -> Bool {
        if kind == .operatorKind || kind == .subscriptKind {
            return true
        }
        let base = name.prefix { $0 != "(" }
        if kind == .function, let first = base.first, !first.isLetter, first != "_" {
            return true
        }
        if kind == .function, base == "callAsFunction" {
            return true
        }
        if kind == .function, base.hasPrefix("build"), containerAttributes.contains("resultBuilder") {
            return true
        }
        return kind == .variable && (name == "wrappedValue" || name == "projectedValue") && containerAttributes.contains("propertyWrapper")
    }
}
