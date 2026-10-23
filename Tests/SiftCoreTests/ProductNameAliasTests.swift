//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the environment prefix a hyphenated binary name derives, and the extra command names the install script links.
struct ProductNameAliasTests {
    @Test
    func aHyphenatedBinaryNameDerivesAnUnderscoredPrefix() {
        let name = ProductName(word: "gizmo-kit", displayName: "GizmoKit")

        #expect(name.environmentPrefix == "GIZMO_KIT_")
        #expect(name.environmentVariable("HOME") == "GIZMO_KIT_HOME")
        #expect(ProductName.current.environmentPrefix == "SWIFT_SURE_")
    }

    @Test
    func theInstallScriptLinksTheAliasesTheNameDeclares() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Distribution/install.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        let assigned = text.split(separator: "\n").first { $0.hasPrefix("ALIAS_NAMES=") }
            .map { $0.dropFirst("ALIAS_NAMES=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }

        #expect(assigned == ProductName.aliases.joined(separator: " "))
    }

    @Test
    func anAliasIsNotAnEarlierProduct() {
        #expect(ProductName.recognised.map(\.word) == ([ProductName.current] + ProductName.legacy).map(\.word))
    }
}
