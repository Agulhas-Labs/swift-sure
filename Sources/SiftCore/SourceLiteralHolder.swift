//
// Copyright © Agulhas Labs
//

import Foundation
import SwiftParser
import SwiftSyntax

extension SourceLiteralSearch.Site {
    /// A property whose value is the literal: a stored `let`/`var` initialised with it, or a computed one returning it, either directly or as the argument of a localisation call (`NSLocalizedString("key", value: "text", comment: "")`, `String(localized: "text")`).
    ///
    /// A property merely containing the literal somewhere in its value is no holder: a SwiftUI `var body: some View { Text("text") }` shows the text but is not named for it, and its uses are every view on the screen.
    struct Holder: Equatable {
        /// The name the property is written by.
        let name: String
        /// The line the property is declared on.
        let line: Int
        /// Whether only the declaring file can write the name: the property is `private` or `fileprivate`.
        let isFileLocal: Bool
        /// Whether the property is `static` or `class`, so only the type's own name reaches it.
        let isStatic: Bool
        /// The declaring type written through its enclosing types, `Outer.Inner`; `nil` for a property outside every type.
        let typeChain: String?

        /// The property `declaration` names in `file`, or `nil` where it names anything else, or holds the literal as part of a larger value.
        init?(declaration: RunFailureSites.Declaration, in file: ParsedFile, source: String) {
            guard let symbol = file.symbols.last(where: { $0.line == declaration.startLine && $0.endLine == declaration.endLine }),
                  symbol.kind == .variable,
                  Self.value(of: declaration, in: source).map(Self.isLiteralHolding) == true
            else {
                return nil
            }
            name = CallSiteScanner.baseName(of: symbol.name)
            line = symbol.line
            isFileLocal = symbol.accessLevel <= .fileprivateLevel
            isStatic = symbol.isStatic
            var chain: [String] = []
            var parent = symbol.parentIndex
            while let current = parent {
                chain.insert(file.symbols[current].name, at: 0)
                parent = file.symbols[current].parentIndex
            }
            typeChain = chain.isEmpty ? nil : chain.joined(separator: ".")
        }

        /// The expression the property's value is: its initializer, or the one expression its getter holds, `return` or not.
        private static func value(of declaration: RunFailureSites.Declaration, in source: String) -> ExprSyntax? {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            guard declaration.startLine >= 1, declaration.startLine <= declaration.endLine, declaration.endLine <= lines.count else { return nil }
            let slice = lines[(declaration.startLine - 1) ..< declaration.endLine].joined(separator: "\n")
            let tree = Parser.parse(source: slice)
            guard let variable = tree.statements.first?.item.as(VariableDeclSyntax.self),
                  let binding = variable.bindings.first
            else { return nil }
            if let initial = binding.initializer?.value {
                return initial
            }
            var body: CodeBlockItemListSyntax?
            switch binding.accessorBlock?.accessors {
            case let .getter(statements):
                body = statements
            case let .accessors(accessors):
                body = accessors.first { $0.accessorSpecifier.tokenKind == .keyword(.get) }?.body?.statements
            case nil:
                return nil
            }
            guard let statements = body, statements.count == 1, let item = statements.first?.item else { return nil }
            return item.as(ReturnStmtSyntax.self)?.expression ?? item.as(ExprSyntax.self)
        }

        /// Whether `expression` is a string literal, or a localisation call with a string literal for an argument.
        private static func isLiteralHolding(_ expression: ExprSyntax) -> Bool {
            if expression.is(StringLiteralExprSyntax.self) {
                return true
            }
            guard let call = expression.as(FunctionCallExprSyntax.self) else { return false }
            let callee = call.calledExpression.trimmedDescription.lowercased()
            let labels = call.arguments.compactMap { $0.label?.text.lowercased() }
            guard callee.contains("localiz") || labels.contains("localized") else { return false }
            return call.arguments.contains { $0.expression.is(StringLiteralExprSyntax.self) }
        }

        /// Whether a write of the name at `use` can be this property: always for an instance property; for a `static` one only `Type.name`, `Self.name`, or the bare name inside the declaring type.
        func reaches(_ use: StringsAccessorFollow.Site) -> Bool {
            guard isStatic else { return true }
            let escaped = NSRegularExpression.escapedPattern(for: name)
            var qualifiers = ["Self"]
            if let last = typeChain?.split(separator: ".").last {
                qualifiers.append(String(last))
            }
            if qualifiers.contains(where: { use.text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0))\\.\(escaped)\\b", options: .regularExpression) != nil }) {
                return true
            }
            guard let chain = typeChain, use.enclosing.hasPrefix(chain + ".") else { return false }
            return use.text.range(of: "(?<![\\w.])\(escaped)\\b", options: .regularExpression) != nil
        }

        /// `uses` as the answer lists them: the declaring file's first, then the other files of the declaring type, then the rest, each group in the order given.
        func ranked(_ uses: [StringsAccessorFollow.Site], declaredIn path: String) -> [StringsAccessorFollow.Site] {
            func tier(_ use: StringsAccessorFollow.Site) -> Int {
                if use.path == path {
                    return 0
                }
                if let chain = typeChain, use.enclosing.hasPrefix(chain + ".") {
                    return 1
                }
                return 2
            }
            return uses.enumerated().sorted { (tier($0.element), $0.offset) < (tier($1.element), $1.offset) }.map(\.element)
        }
    }
}

/// Which property-held rows have had their uses printed in one answer: each once, and the first ``SourceLiteralSearch/propertyUseCap`` in the order printed.
final class PropertyTrailLedger {
    private var printed: Set<String> = []
    /// The names of the holders admitted, in the order admitted.
    private(set) var admittedNames: [String] = []

    /// Whether the uses of `holder` held by the literal at `path` are to be printed now.
    func admits(_ holder: SourceLiteralSearch.Site.Holder, path: String) -> Bool {
        let key = "\(path):\(holder.line)"
        guard !printed.contains(key), printed.count < SourceLiteralSearch.propertyUseCap else { return false }
        printed.insert(key)
        admittedNames.append(holder.name)
        return true
    }
}
