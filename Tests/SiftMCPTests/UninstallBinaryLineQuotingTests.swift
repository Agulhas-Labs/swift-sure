//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The `rm` line `swift-sure uninstall` prints is a command the user pastes, so a path that needs quoting is quoted.
struct UninstallBinaryLineQuotingTests {
    @Test func aPathWithASpaceIsQuotedInTheRmLine() {
        let line = BinaryRemoval.line(for: "/opt/one two/bin/swift-sure")

        #expect(line == "rm '/opt/one two/bin/swift-sure' — a running binary does not delete itself")
    }

    @Test func aPathWithASingleQuoteIsEscapedInTheRmLine() {
        let line = BinaryRemoval.line(for: "/opt/it's/bin/swift-sure")

        #expect(line == #"rm '/opt/it'\''s/bin/swift-sure' — a running binary does not delete itself"#)
    }

    @Test func anOrdinaryPathStaysBare() {
        let line = BinaryRemoval.line(for: "/opt/bin/swift-sure")

        #expect(line == "rm /opt/bin/swift-sure — a running binary does not delete itself")
    }
}
