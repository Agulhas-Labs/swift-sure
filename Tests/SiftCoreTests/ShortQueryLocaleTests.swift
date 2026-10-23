//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A short query folds case by the locale's rules, as an ordinary literal does, so Turkish dotted and dotless i match their pairs.
struct ShortQueryLocaleTests {
    @Test
    func aDottedCapitalIMatchesItsLowercaseUnderTurkishRules() {
        let turkish = Locale(identifier: "tr_TR")

        #expect(ShortQueryMatch.contains("id", query: "\u{130}D", ignoringCase: true, locale: turkish))
        #expect(ShortQueryMatch.firstRange(in: "user id", query: "\u{130}D", ignoringCase: true, locale: turkish) != nil)
    }

    @Test
    func theSameQueryDoesNotMatchUnderANeutralLocale() {
        let english = Locale(identifier: "en_US")

        #expect(!ShortQueryMatch.contains("id", query: "\u{130}D", ignoringCase: true, locale: english))
    }
}
