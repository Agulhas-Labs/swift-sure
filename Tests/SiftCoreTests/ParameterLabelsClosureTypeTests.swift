//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import SwiftParser
import SwiftSyntax
import Testing

/// Covers which parameters a trailing closure may fill: only one whose written type does not rule a closure out.
struct ParameterLabelsClosureTypeTests {
    private static func labels(_ signature: String, _ name: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) throws -> ParameterLabels {
        try #require(ParameterLabels(signature: signature, name: name, standardNames: ClosureParameterType.closedNames), sourceLocation: sourceLocation)
    }

    /// The arguments of the one call in a line of source.
    private static func written(_ call: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) throws -> WrittenArguments {
        let tree = Parser.parse(source: call)
        let expression = try #require(tree.statements.first?.item.as(FunctionCallExprSyntax.self), sourceLocation: sourceLocation)
        return WrittenArguments(of: expression)
    }

    /// Whether `x.f { }` can call `func f(_ value: <type>)`.
    private static func takes(_ type: String, generics: String = "") throws -> Bool {
        try labels("func f\(generics)(_ value: \(type))", "f(_:)").accepts(written("x.f {}"))
    }

    @Test
    func aTrailingClosureCannotFillAStringParameter() throws {
        let labels = try Self.labels("func merging(_ message: String, with note: String)", "merging(_:with:)")

        #expect(try !labels.accepts(Self.written("x.merging(a) { $1 }")))
        #expect(try labels.accepts(Self.written("x.merging(a, with: b)")))
    }

    @Test(arguments: ["[String]", "[String: Int]", "(Int, Int)", "Swift.String", "inout String", "String?", "String!", "Optional<String>", "(String)", "Array<Int>", "borrowing Data", "URL"])
    func aTypeThatIsNotAFunctionRejectsAClosure(type: String) throws {
        #expect(try !Self.takes(type))
    }

    @Test(arguments: ["() -> Void", "(() -> Void)?", "@escaping @Sendable () -> Void", "@autoclosure () -> Bool", "some P", "any P", "Any", "Handler", "Optional<() -> Void>", "P & Q", "()"])
    func aTypeThatMayBeAFunctionAcceptsAClosure(type: String) throws {
        #expect(try Self.takes(type))
    }

    @Test
    func genericParametersAndPacksAcceptAClosure() throws {
        #expect(try Self.takes("T", generics: "<T>"))
        #expect(try Self.takes("Data", generics: "<Data>"))
        #expect(try Self.takes("repeat each T", generics: "<each T>"))
        #expect(try !Self.takes("Data", generics: "<T>"))
    }

    @Test
    func aDefaultedStringParameterIsSkippedForAFunctionOne() throws {
        let labels = try Self.labels(#"func f(_ a: Int, b: String = "", c: () -> Void)"#, "f(_:b:c:)")

        #expect(try labels.accepts(Self.written("x.f(1) {}")))
    }

    @Test
    func aLabeledTrailingClosureMustFillAFunctionParameter() throws {
        let rejecting = try Self.labels("func f(_ a: () -> Void, done: String)", "f(_:done:)")
        let accepting = try Self.labels("func f(_ a: () -> Void, done: () -> Void)", "f(_:done:)")

        #expect(try !rejecting.accepts(Self.written("x.f {} done: {}")))
        #expect(try accepting.accepts(Self.written("x.f {} done: {}")))
    }

    /// Whether `x.f { }` can call `func f(_ value: <type>)` where `standardNames` are vouched for.
    private static func takes(_ type: String, standardNames: Set<String>, sourceLocation: Testing.SourceLocation = #_sourceLocation) throws -> Bool {
        try #require(ParameterLabels(signature: "func f(_ value: \(type))", name: "f(_:)", standardNames: standardNames), sourceLocation: sourceLocation).accepts(written("x.f {}", sourceLocation: sourceLocation))
    }

    @Test
    func aMemberTypeOtherThanSwiftOrFoundationAcceptsAClosure() throws {
        #expect(try Self.takes("Gizmo.Data", standardNames: ["Data"]))
        #expect(try !Self.takes("Swift.String", standardNames: []))
        #expect(try !Self.takes("Foundation.URL", standardNames: []))
    }

    @Test
    func aBareStandardNameRulesAClosureOutOnlyWhereVouchedFor() throws {
        #expect(try Self.takes("String", standardNames: []))
        #expect(try !Self.takes("String", standardNames: ["String"]))
        #expect(try Self.takes("Data", standardNames: ["String"]))
    }

    @Test
    func aMemberwisePropertyIsJudgedBindingByBinding() {
        let tree = Parser.parse(source: "var tap = { }, count: Int = 0\nvar a, b: Int\nvar title: String, tap: () -> Void\nvar loose")
        let declarations = tree.statements.compactMap { $0.item.as(VariableDeclSyntax.self) }
        let first = Array(declarations[0].bindings)
        let pair = Array(declarations[1].bindings)
        let mixed = Array(declarations[2].bindings)

        #expect(ClosureParameterType.takesClosure(bindings: first, standardNames: ["Int"]))
        #expect(!ClosureParameterType.takesClosure(bindings: Array(first.dropFirst()), standardNames: ["Int"]))
        #expect(!ClosureParameterType.takesClosure(bindings: pair, standardNames: ["Int"]))
        #expect(ClosureParameterType.takesClosure(bindings: Array(mixed.dropFirst())))
        #expect(!ClosureParameterType.takesClosure(bindings: mixed, standardNames: ["String"]))
        #expect(ClosureParameterType.takesClosure(bindings: Array(declarations[3].bindings)))
    }

    @Test
    func aVariadicIsJudgedByItsElementType() throws {
        let ints = try Self.labels("func f(_ values: Int...)", "f(_:)")
        let closures = try Self.labels("func f(_ values: (() -> Void)...)", "f(_:)")

        #expect(try !ints.accepts(Self.written("x.f {}")))
        #expect(try closures.accepts(Self.written("x.f {}")))
    }
}

private extension ParameterLabels {
    /// Whether a call written with `arguments` can be a call of an instance method with these labels.
    func accepts(_ arguments: WrittenArguments) -> Bool {
        accepts(arguments, takesInstance: true)
    }
}
