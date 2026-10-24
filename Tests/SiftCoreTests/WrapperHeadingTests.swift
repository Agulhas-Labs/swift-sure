//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The wrapper-attribute-sites block's heading is short and distinguishable from a plain name-matched block, and the rule behind it lives in `swift-sure help answers`.
struct WrapperHeadingTests {
    static var site: SyntacticCallSite {
        SyntacticCallSite(path: "Sources/App/Use.swift", line: 4, enclosing: "make()")
    }

    /// The heading is short, still opening with the block reader's required prefix, but naming the rule this block follows so it reads differently from a plain name-matched block.
    @Test
    func theGroupedHeadingIsShortAndDistinguishable() {
        let lines = WrapperAttributeSites.lines([Self.site], named: "Clamp", for: "init(wrappedValue:)", cap: 20)

        #expect(lines.contains(
            "syntactic call sites — by written name where the index store records no call — see swift-sure help answers (call sites)"
        ), "\(lines)")
        #expect(lines.first { $0.hasPrefix("syntactic call sites") }?.utf8.count ?? .max <= 160, "\(lines)")
    }

    /// `swift-sure help answers` states the rule the short heading now only points at: an unrecorded `@T` attribute site is listed beside a resolved answer, kept only where the store records a reference to that very type, each under the one initializer its labels reach.
    @Test
    func helpAnswersStatesTheWrapperAttributeRule() {
        let body = HelpTopics.topic(named: "answers")?.body ?? ""

        #expect(body.contains("a property wrapper's @T attribute sites the store records no call at"), "\(body)")
    }
}
