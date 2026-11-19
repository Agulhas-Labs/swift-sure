//
// Copyright © Agulhas Labs
//

import Foundation
import SwiftSyntax

/// The lines on which a member's name is written qualified by the type that owns it, `Owner.member`: the part of a too-common name's sites that still narrows.
///
/// A name like `line` or `run` is written in so much of a repository that its bare sites stop counting as evidence (`AffectedRenderer.nameEvidenceFileCap`), and a route through a member of that name was dropped with them: a test calling `Gizmo.line(for:)` never reached a change through it. The spelling `Gizmo.line` is as narrow as the type's own name, so it is kept where the bare name is not. Only an explicit owner counts: `Self.line`, `x.line` and a bare `line` inside the owner's own body are left out, since telling them apart from another type's member needs the resolution a cold store cannot give.
struct OwnerQualifiedMentions {
    /// The reader `narrowing` uses unless given one, bound per task so a test can count the files a walk reads.
    @TaskLocal static var reader: @Sendable (String) -> Data? = { FileManager.default.contents(atPath: $0) }

    /// The sites of a too-common `name` that write it as a member of a type owning one of the declarations it was taken from, or none when no origin is a member of a type, with the first of those owners, sorted, for the note to show.
    static func sites(_ sites: [NameMention], name: String, from origins: [SymbolRow], spellings: MemberSpellings, store: IndexStore, rootPath: String) throws -> (sites: [NameMention], owner: String?) {
        var owners: Set<String> = []
        var homes: [String: Set<String>] = [:]
        for origin in origins {
            guard let owner = try store.parentChain(of: origin).last, owner.kind.isTypeDeclaration || owner.kind == .extensionKind else { continue }
            let ownerName = DeclaredTypeName.last(ofPath: owner.name)
            owners.insert(ownerName)
            homes[owner.path, default: []].insert(ownerName)
            // An extension's own file need not declare the type; the type's declaration in the extension's module is the owner's home too.
            if owner.kind == .extensionKind {
                for declaration in try store.symbols(named: ownerName) where declaration.kind.isTypeDeclaration && declaration.module == owner.module {
                    homes[declaration.path, default: []].insert(ownerName)
                }
            }
        }
        return (narrowing(sites, name: name, owners: owners, homes: homes, spellings: spellings, rootPath: rootPath), owners.min())
    }

    /// The sites among `sites` whose line writes `name` as a member of one of `owners`, read from the files under `rootPath`.
    ///
    /// A file is parsed only if its text spells `Owner.name` or `<…>.name` (a specialized owner, `Owner<T>.name`), since the name is too common for its own spelling to rule a file out and this check runs inside the reach line's time budget; `Owner\n    .name` split across lines is missed. Its tree is dropped before the next file is read. A file whose `spellings`, recorded by the scan that found the sites, show it spells neither is not read at all; one without a record is read. The record compares bytes, so an owner spelled with a canonically equivalent but different character (a Kelvin sign for `K`), which Swift does not take as the same identifier, no longer passes.
    ///
    /// A file that declares a type of an owner's name itself at file scope, such as a test's `private enum Gizmo`, means its own type by an unqualified `Gizmo.name` or `Gizmo<T>.name`, so those sites are not admitted; a module-qualified `Lib.Gizmo.name` there still is, and the file's sites of other owners are judged on their own. `homes` names, by path, the owners whose real declaration that file holds, which stay admitted. A shadowing type declared in another file of the same module is not seen, since each file is read alone, so `Gizmo.name` written beside it is still admitted.
    static func narrowing(
        _ sites: [NameMention],
        name: String,
        owners: Set<String>,
        homes: [String: Set<String>] = [:],
        spellings: MemberSpellings = MemberSpellings(),
        rootPath: String,
        read: (String) -> Data? = { reader($0) }
    ) -> [NameMention] {
        guard !owners.isEmpty else { return [] }
        var kept: [NameMention] = []
        for (path, inFile) in Dictionary(grouping: sites, by: \.path).sorted(by: { $0.key < $1.key }) {
            guard spellings.mayQualify(name, path: path, owners: owners),
                  let data = read(rootPath + "/" + path),
                  let source = String(data: data, encoding: .utf8),
                  owners.contains(where: { source.contains("\($0).\(name)") }) || source.contains(">.\(name)") else { continue }
            let lines = NestingGate.parseOrEmpty(source) { tree in
                let visitor = Visitor(name: name, owners: owners, converter: SourceLocationConverter(fileName: path, tree: tree))
                visitor.walk(tree)
                let shadowed = visitor.declaredTypes.subtracting(homes[path] ?? [])
                return Set(visitor.accesses.filter { $0.isQualified || !shadowed.contains($0.owner) }.map(\.line))
            }
            kept += inFile.filter { lines.contains($0.line) }
        }
        return kept
    }
}

private extension OwnerQualifiedMentions {
    /// One `Owner.name` access: its line, its owner's simple name, and whether the owner is itself qualified (`Module.Owner.name`).
    struct Access {
        let line: Int
        let owner: String
        let isQualified: Bool
    }

    /// Records every `Owner.name` member access, reading the owner as the last component of the base, so `Module.Owner.name` and `Owner<T>.name` count too, and the simple names of the types the file declares.
    final class Visitor: SyntaxVisitor {
        private let name: String
        private let owners: Set<String>
        private let converter: SourceLocationConverter
        var accesses: [Access] = []
        var declaredTypes: Set<String> = []

        init(name: String, owners: Set<String>, converter: SourceLocationConverter) {
            self.name = name
            self.owners = owners
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if node.declName.baseName.text == name, let base = node.base, let found = Self.lastName(of: base), owners.contains(found.owner) {
                accesses.append(Access(line: converter.location(for: node.declName.baseName.positionAfterSkippingLeadingTrivia).line, owner: found.owner, isQualified: found.isQualified))
            }
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            declare(node.name)
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            declare(node.name)
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            declare(node.name)
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            declare(node.name)
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            declare(node.name)
        }

        /// Records a type the file declares at file scope, the only kind that shadows the owner for the whole file.
        ///
        /// A nested or local one is in scope only inside its parent, where the real type can still be meant outside it, and a typealias is most often the real type under its own name; both are left out, so they over-admit rather than drop reach.
        private func declare(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
            guard token.parent?.parent?.parent?.parent?.is(SourceFileSyntax.self) == true else { return .visitChildren }
            declaredTypes.insert(token.text)
            return .visitChildren
        }

        /// The owner a base names, and whether it is written under a qualifier of its own.
        static func lastName(of base: ExprSyntax) -> (owner: String, isQualified: Bool)? {
            if let reference = base.as(DeclReferenceExprSyntax.self) {
                return (reference.baseName.text, false)
            }
            if let member = base.as(MemberAccessExprSyntax.self) {
                return (member.declName.baseName.text, true)
            }
            if let specialized = base.as(GenericSpecializationExprSyntax.self) {
                return lastName(of: specialized.expression)
            }
            return nil
        }
    }
}
