//
// Copyright © Agulhas Labs
//

import SwiftSyntax

/// Whether a type's name written bare is the qualifier of a name written after it, `Net` in `Net.URL` or `Net.make()`, where a module of the name, which a file importing it may mean, can stand as well as a type.
///
/// Only a following identifier counts: `Net.self` and `Net.init` can be written on a type alone, and a module takes no generic arguments, so `Net<Int>.Inner` names the type.
struct QualifyingTypeName {
    /// `site`, a type use at `node`, marked as written bare before a `.` and a name.
    static func marking(_ site: SyntacticCallSite, at node: some SyntaxProtocol) -> SyntacticCallSite {
        var marked = site
        marked.qualifiesAName = site.qualifier == nil && qualifies(Syntax(node))
        return marked
    }

    /// Whether `node`, a bare type name in a type or an expression, is the base of a member type or a member access naming an identifier.
    static func qualifies(_ node: Syntax) -> Bool {
        if let type = node.as(IdentifierTypeSyntax.self) {
            return type.genericArgumentClause == nil && node.parent?.as(MemberTypeSyntax.self)?.baseType.id == node.id
        }
        guard let access = node.parent?.as(MemberAccessExprSyntax.self), access.base?.id == node.id else { return false }
        if case .identifier = access.declName.baseName.tokenKind {
            return true
        }
        return false
    }
}
