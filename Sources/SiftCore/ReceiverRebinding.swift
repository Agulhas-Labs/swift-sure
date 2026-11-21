//
// Copyright © Agulhas Labs
//

import Foundation
import SwiftParser
import SwiftSyntax

/// Whether a source file rebinds a type name, so that the name written there may not be the type the index declares under it.
///
/// A file rebinds a name where its parse introduces the name anywhere: as a generic parameter, a pattern's identifier (`let`, `var`, a tuple, `for`, `case let`, `if let`, `catch`), a closure capture, a closure, function, initializer, subscript or enum-case parameter name, the name of a type, protocol, typealias, associated type or macro, either side of a same-type requirement or the left side of a conformance requirement of a `where` clause; the reading is generous, not scope-aware, since a miss hides a use. The same parse records where the file's type, extension and protocol declarations lie, since inside one a conformance or a generic extension can bring an associated type or a generic parameter of any name into scope unwritten (`extension [Gizmo]` binds `Element`). A file that cannot be parsed rebinds every name. The tree is discarded once the names and ranges are read (Docs/Design.md §2).
struct ReceiverRebinding {
    /// Whether `source` rebinds `name`.
    static func rebinds(_ name: String, in source: UnsafeRawBufferPointer) -> Bool {
        Memo().rebinds(name, in: source)
    }

    /// The names the parse of `source` introduces and the byte ranges of its type, extension and protocol declarations, or `nil` where it cannot be parsed.
    fileprivate static func reading(of source: UnsafeRawBufferPointer) -> Reading? {
        guard let text = String(bytes: source, encoding: .utf8) else { return nil }
        return NestingGate.parse(text) { tree in
            let collector = Collector(viewMode: .sourceAccurate)
            collector.walk(tree)
            return Reading(names: collector.names, declarations: collector.declarations)
        }
    }
}

extension ReceiverRebinding {
    /// What one parse of a file yields.
    fileprivate struct Reading {
        let names: Set<String>
        /// The outermost type, extension and protocol declarations, in byte order.
        let declarations: [Range<Int>]
    }

    /// The names one file introduces and where its type declarations lie, read once when the first name is asked about however many lines write it.
    final class Memo {
        private var reading: Reading??

        /// Whether `source` rebinds `name`; every name where it cannot be parsed.
        func rebinds(_ name: String, in source: UnsafeRawBufferPointer) -> Bool {
            guard let known = read(source) else { return true }
            return known.names.contains(name)
        }

        /// Whether the byte at `offset` lies inside a type, extension or protocol declaration of `source`; true where it cannot be parsed.
        func isInsideTypeDeclaration(_ offset: Int, in source: UnsafeRawBufferPointer) -> Bool {
            guard let known = read(source) else { return true }
            return known.declarations.contains { $0.contains(offset) }
        }

        private func read(_ source: UnsafeRawBufferPointer) -> Reading? {
            if reading == nil {
                reading = .some(ReceiverRebinding.reading(of: source))
            }
            guard case let .some(.some(known)) = reading else { return nil }
            return known
        }
    }
}

private extension ReceiverRebinding {
    final class Collector: SyntaxVisitor {
        private(set) var names: Set<String> = []
        private(set) var declarations: [Range<Int>] = []

        private func add(_ token: TokenSyntax?) {
            guard let token else { return }
            names.insert(token.text.trimmingCharacters(in: CharacterSet(charactersIn: "`")))
        }

        private func addTokens(of type: some SyntaxProtocol) {
            for token in type.tokens(viewMode: .sourceAccurate) where token.tokenKind != .period {
                add(token)
            }
        }

        /// Records `node` as a type declaration unless it lies inside one already recorded.
        private func enclose(_ node: some SyntaxProtocol) {
            let range = node.positionAfterSkippingLeadingTrivia.utf8Offset ..< node.endPositionBeforeTrailingTrivia.utf8Offset
            if let last = declarations.last, last.contains(range.lowerBound) {
                return
            }
            declarations.append(range)
        }

        override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            return .visitChildren
        }

        override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
            add(node.identifier)
            return .visitChildren
        }

        override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            return .visitChildren
        }

        override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
            add(node.firstName)
            add(node.secondName)
            return .visitChildren
        }

        override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
            add(node.firstName)
            add(node.secondName)
            return .visitChildren
        }

        override func visit(_ node: EnumCaseParameterSyntax) -> SyntaxVisitorContinueKind {
            add(node.firstName)
            add(node.secondName)
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            enclose(node)
            return .visitChildren
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            enclose(node)
            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            enclose(node)
            return .visitChildren
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            enclose(node)
            return .visitChildren
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            enclose(node)
            return .visitChildren
        }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            enclose(node)
            return .visitChildren
        }

        override func visit(_ node: ClosureCaptureSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            return .visitChildren
        }

        override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            return .visitChildren
        }

        override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            return .visitChildren
        }

        override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
            add(node.name)
            return .visitChildren
        }

        override func visit(_ node: SameTypeRequirementSyntax) -> SyntaxVisitorContinueKind {
            addTokens(of: node.leftType)
            addTokens(of: node.rightType)
            return .visitChildren
        }

        override func visit(_ node: ConformanceRequirementSyntax) -> SyntaxVisitorContinueKind {
            addTokens(of: node.leftType)
            return .visitChildren
        }
    }
}
