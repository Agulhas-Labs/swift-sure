//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how a failure's signature folds a string literal: whole, whatever the literal holds.
struct RunSignatureLiteralTests {
    /// The quotes of a literal nested in an interpolation do not end the literal that holds it.
    @Test
    func aLiteralWithANestedLiteralInAnInterpolationFoldsWhole() {
        let signature = RunFailureSignature(message: ##"fetch(#line, "\(tag("#"))") == "ok""##)

        #expect(signature.text == #"fetch(#line, "…") == "…""#)
    }
}
