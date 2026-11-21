//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A file rebinds a type name where its parse introduces the name anywhere, whatever form the binding takes.
struct ReceiverRebindingTests {
    private static func rebinds(_ name: String, in text: String) -> Bool {
        Array(text.utf8).withUnsafeBytes { ReceiverRebinding.rebinds(name, in: $0) }
    }

    @Test
    func aGenericParameterIsRebound() {
        #expect(Self.rebinds("Item", in: "func f<Item: Base>() {}"))
        #expect(Self.rebinds("Gadget", in: "struct Holder<Gadget: Base> {}"))
        #expect(Self.rebinds("Item", in: "func f<each Item: Base>() {}"))
        #expect(Self.rebinds("Item", in: "func f<A, Item>() {}"))
    }

    @Test
    func commentsInAClauseDoNotHideTheName() {
        #expect(Self.rebinds("Item", in: "func f<\n    // the element\n    Item\n>() {}"))
        #expect(Self.rebinds("Item", in: "func f<A, /* the element */ Item>() {}"))
        #expect(Self.rebinds("Item", in: "func f<A, // { a brace; and a semicolon\n    Item>() {}"))
    }

    @Test
    func aLocalTypeIsRebound() {
        #expect(Self.rebinds("Local", in: "func f() { class Local: Base {} }"))
        for word in ["struct", "enum", "actor", "protocol"] {
            #expect(Self.rebinds("Item", in: "\(word) Item {}"), "\(word)")
        }

        #expect(Self.rebinds("Item", in: "typealias Item = Base"))
        #expect(Self.rebinds("Item", in: "protocol P { associatedtype Item }"))
    }

    @Test
    func aPatternBindingIsRebound() {
        #expect(Self.rebinds("Item", in: "let Item: Base.Type = Sub.self"))
        #expect(Self.rebinds("Gadget", in: "let (Gadget, n) = (Sub.self, 1)"))
        #expect(Self.rebinds("Local", in: "for Local in [Sub.self] as [Base.Type] { _ = names.map(Local.init) }"))
        #expect(Self.rebinds("Local", in: "if let Local = maybe {}"))
        #expect(Self.rebinds("Local", in: "switch x { case let .some(Local): break default: break }"))
        #expect(Self.rebinds("Local", in: "do {} catch let Local {}"))
    }

    @Test
    func aParameterNameIsRebound() {
        #expect(Self.rebinds("Gadget", in: "func f(_ Gadget: Base.Type) {}"))
        #expect(Self.rebinds("Gadget", in: "func f(Gadget inner: Base.Type) {}"))
        #expect(Self.rebinds("Gadget", in: "init(label Gadget: Base.Type) {}"))
        #expect(Self.rebinds("Gadget", in: "subscript(Gadget: Int) -> Int { 0 }"))
        #expect(Self.rebinds("Gadget", in: "enum E { case a(Gadget: Int) }"))
    }

    @Test
    func aClosureParameterIsRebound() {
        #expect(Self.rebinds("Local", in: "let make: (Base.Type, [String]) -> [Base] = { Local, names in names.map(Local.init) }"))
        #expect(Self.rebinds("Gadget", in: "let f = { Gadget in Gadget.init }"))
        #expect(Self.rebinds("Gadget", in: "let f = { (Gadget) in Gadget.init }"))
        #expect(Self.rebinds("Gadget", in: "let f = { (Gadget: Base.Type) in Gadget.init }"))
    }

    @Test
    func aWhereClauseRequirementNamesAnOuterGeneric() {
        #expect(Self.rebinds("Element", in: "extension Array where Element == Sub { static func m(_ n: [String]) -> [Element] { n.map(Element.init) } }"))
        #expect(Self.rebinds("Gadget", in: "func f<A>() where A: Collection, Gadget == Int {}"))
        #expect(Self.rebinds("Gadget", in: "extension Holder where Gadget: Base {}"))
    }

    @Test
    func aNameOnlyUsedIsNotRebound() {
        #expect(!Self.rebinds("Item", in: "let x = Item.init"))
        #expect(!Self.rebinds("String", in: "let counts: [String: Int] = [:]\n_ = names.map(String.init)"))
        #expect(!Self.rebinds("String", in: "let s = \"class String {}\"\n_ = names.map(String.init)"))
        #expect(!Self.rebinds("Item", in: "let a = x < y; let b = (c, Item)"))
        #expect(!Self.rebinds("Item", in: "let s = \"\\(a // b)\"\n_ = names.map(Item.init)"))
    }

    @Test
    func aFileThatCannotBeParsedRebindsEveryName() {
        let nested = String(repeating: "[", count: NestingGate.maximumTypeChain + 10)

        #expect(Self.rebinds("Anything", in: nested))
    }

    @Test
    func aMemoAnswersAsTheFileDoes() {
        let text = "struct Item {}\nlet x = Other.init"
        let memo = ReceiverRebinding.Memo()
        Array(text.utf8).withUnsafeBytes { source in
            #expect(memo.rebinds("Item", in: source))
            #expect(memo.rebinds("Item", in: source))
            #expect(!memo.rebinds("Other", in: source))
        }
    }

    @Test
    func aClosureCaptureAndEitherSideOfASameTypeRequirementAreRebound() {
        #expect(Self.rebinds("Element", in: "let f = { [Element = Gizmo.self] (n: [String]) in n.map(Element.init) }"))
        #expect(Self.rebinds("Element", in: "extension Array where Gizmo == Element {}"))
    }

    @Test
    func aMemoKnowsWhereTypeDeclarationsLie() {
        let text = "let a = 1\n@Wrapper struct S { let b = 2 }\nextension S { enum E {} }\nprotocol P {}\nlet c = 3"
        let memo = ReceiverRebinding.Memo()
        let offsets = ["a =", "@Wrapper", "b =", "E {", "P {", "c ="].compactMap { text.range(of: $0).map { text.distance(from: text.startIndex, to: $0.lowerBound) } }
        let inside = Array(text.utf8).withUnsafeBytes { source in offsets.map { memo.isInsideTypeDeclaration($0, in: source) } }
        let unparsable = Array(String(repeating: "[", count: NestingGate.maximumTypeChain + 10).utf8).withUnsafeBytes { ReceiverRebinding.Memo().isInsideTypeDeclaration(0, in: $0) }

        #expect(inside == [false, true, true, true, true, false])
        #expect(unparsable)
    }
}
