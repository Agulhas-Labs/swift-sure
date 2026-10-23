//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Covers the names derived from the product name: today's values stay byte-identical, and a different name carries through every derived one.
struct ProductNameTests {
    @Test
    func theCurrentNameDerivesTodaysValues() {
        let name = ProductName.current

        #expect(name.binary == "swift-sure")
        #expect(name.directoryName == ".swift-sure")
        #expect(name.configFileName == ".swift-sure.json")
        #expect(name.backupSuffix == ".bak-swift-sure")
        #expect(name.mcpServer == "swift-sure")
        #expect(name.toolPrefix == "mcp__swift-sure__")
        #expect(name.shareDirectory == "swift-sure")
        #expect(name.ruleFileName == "SwiftSure.md")
        #expect(name.environmentVariable("HOME") == "SWIFT_SURE_HOME")
        #expect(EnvironmentVariable.home.name == "SWIFT_SURE_HOME")
    }

    @Test
    func everyEnvironmentVariableIsDeclared() {
        #expect(EnvironmentVariable.allCases.count == 16)
        #expect(Set(EnvironmentVariable.allCases.map(\.name)).count == 16)
        #expect(EnvironmentVariable.allCases.allSatisfy { $0.name.hasPrefix("SWIFT_SURE_") })
    }

    @Test
    func anotherNameCarriesThroughEveryDerivedOne() {
        let name = ProductName(word: "gizmo", displayName: "Gizmo")

        #expect(name.binary == "gizmo")
        #expect(name.directoryName == ".gizmo")
        #expect(name.configFileName == ".gizmo.json")
        #expect(name.backupSuffix == ".bak-gizmo")
        #expect(name.toolPrefix == "mcp__gizmo__")
        #expect(name.environmentVariable("HOME") == "GIZMO_HOME")
        #expect(name.ruleFileName == "Gizmo.md")
        #expect(name.description == "gizmo")
    }

    @Test
    func theHistoricalNpmPackageIsKept() {
        #expect(ProductName.npmPackage == "@agulhas-labs/sift")
        #expect(SiftClaudeSetup.npmPackage == ProductName.npmPackage)
    }
}
