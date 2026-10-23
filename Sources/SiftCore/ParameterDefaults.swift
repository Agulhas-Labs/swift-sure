//
// Copyright © Agulhas Labs
//

import SwiftSyntax

/// The parameters a declaration's head gives a default value, the one place in a head that runs code and so the one place it can call an initializer.
///
/// Read from the parse of the head or of the declaration's own lines, an enum case's clause parsed as an enum's member: only parameter clauses count, never a body, so a local function's defaults are not its container's, and a `==` or a property's initial value is no default.
struct ParameterDefaults {
    /// Each defaulted parameter, in the order written.
    let parameters: [Parameter]

    /// The defaulted parameters `source` declares outside any body, none for a source with no `=` in it.
    init(source: String) {
        guard source.contains("=") else {
            parameters = []
            return
        }
        let found = Self.parameters(in: source, asEnumMembers: false)
        parameters = found.isEmpty && AccessExposure.names("case", in: source) ? Self.parameters(in: source, asEnumMembers: true) : found
    }

    /// The defaulted parameters' text, each one's type and default value together, one per line.
    var text: String {
        parameters.map(\.text).joined(separator: "\n")
    }

    /// Whether the place at `line` and `column`, both counted from 1 in the parsed source, falls inside a default value.
    func holdsDefault(line: Int, column: Int) -> Bool {
        let place = Place(line: line, column: column)
        return parameters.contains { $0.start <= place && place < $0.end }
    }
}

extension ParameterDefaults {
    /// One defaulted parameter: its written text and where its default value starts and ends.
    struct Parameter {
        let text: String
        let start: Place
        let end: Place
    }

    /// A line and a UTF-8 column in the parsed source, both counted from 1.
    struct Place: Comparable {
        let line: Int
        let column: Int

        static func < (lhs: Place, rhs: Place) -> Bool {
            (lhs.line, lhs.column) < (rhs.line, rhs.column)
        }
    }
}

private extension ParameterDefaults {
    /// The defaulted parameters `source` declares, parsed as written or, where asked, as the members of an enum, where an enum case's clause parses as one, with each place still counted in `source`'s own lines.
    static func parameters(in source: String, asEnumMembers: Bool) -> [Parameter] {
        NestingGate.parseOrEmpty(asEnumMembers ? "enum Cases {\n" + source + "\n}" : source) { tree in
            let converter = SourceLocationConverter(fileName: "", tree: tree)
            let roots: [Syntax] = if asEnumMembers {
                tree.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }.flatMap { $0.memberBlock.members.map { Syntax($0.decl) } }
            } else {
                [Syntax(tree)]
            }
            var found: [Parameter] = []
            for root in roots {
                collect(root, converter: converter, into: &found)
            }
            let shift = asEnumMembers ? 1 : 0
            return found.map { Parameter(text: $0.text, start: Place(line: $0.start.line - shift, column: $0.start.column), end: Place(line: $0.end.line - shift, column: $0.end.column)) }
        }
    }

    /// Every defaulted parameter under `node`, skipping bodies.
    static func collect(_ node: Syntax, converter: SourceLocationConverter, into found: inout [Parameter]) {
        if node.is(CodeBlockSyntax.self) || node.is(AccessorBlockSyntax.self) || node.is(MemberBlockSyntax.self) {
            return
        }
        let defaulted: (parameter: Syntax, value: InitializerClauseSyntax)? = if let parameter = node.as(FunctionParameterSyntax.self), let value = parameter.defaultValue {
            (Syntax(parameter), value)
        } else if let parameter = node.as(EnumCaseParameterSyntax.self), let value = parameter.defaultValue {
            (Syntax(parameter), value)
        } else {
            nil
        }
        if let defaulted {
            let start = converter.location(for: defaulted.value.value.positionAfterSkippingLeadingTrivia)
            let end = converter.location(for: defaulted.value.value.endPositionBeforeTrailingTrivia)
            found.append(Parameter(
                text: defaulted.parameter.trimmedDescription,
                start: Place(line: start.line, column: start.column),
                end: Place(line: end.line, column: end.column)
            ))
            return
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collect(child, converter: converter, into: &found)
        }
    }
}
