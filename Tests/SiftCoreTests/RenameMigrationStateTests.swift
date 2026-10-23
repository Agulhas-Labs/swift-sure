//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// Covers what a rename leaves readable: a name stood in for the product's (`gizmo`) whose predecessor (`swift-sure`) left state behind, and the files that pin the constant to the scripts and the library.
@Suite(.temporaryDirectories)
struct RenameMigrationStateTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]

    @Test
    func anOlderRepositoryDirectoryIsReadWhereTheCurrentOneIsAbsent() throws {
        let root = try TemporaryDirectory.make("migrate-cache")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".swift-sure"), withIntermediateDirectories: true)

        #expect(SiftPaths.cache(in: root, names: Self.names).lastPathComponent == ".swift-sure")

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".gizmo"), withIntermediateDirectories: true)
        #expect(SiftPaths.cache(in: root, names: Self.names).lastPathComponent == ".gizmo")
    }

    @Test
    func aRepositoryWithNeitherDirectoryGetsTheCurrentOneToCreate() throws {
        let root = try TemporaryDirectory.make("migrate-none")

        #expect(SiftPaths.cache(in: root, names: Self.names).lastPathComponent == ".gizmo")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".gizmo").path))
    }

    @Test
    func anOlderConfigFileIsReadWhereTheCurrentOneIsAbsent() throws {
        let root = try TemporaryDirectory.make("migrate-config")
        try Data("{}".utf8).write(to: root.appendingPathComponent(".swift-sure.json"))

        #expect(SiftPaths.config(in: root, names: Self.names).lastPathComponent == ".swift-sure.json")

        try Data("{}".utf8).write(to: root.appendingPathComponent(".gizmo.json"))
        #expect(SiftPaths.config(in: root, names: Self.names).lastPathComponent == ".gizmo.json")
    }

    @Test
    func anOlderHomeVariableIsHonouredAndTheCurrentOneWins() {
        let older = ["SWIFT_SURE_HOME": "/older"]
        let both = ["SWIFT_SURE_HOME": "/older", "GIZMO_HOME": "/current"]

        #expect(EnvironmentVariable.home.value(in: older, names: Self.names) == "/older")
        #expect(EnvironmentVariable.home.value(in: both, names: Self.names) == "/current")
        #expect(SiftPaths.home(environment: older, names: Self.names).path == "/older")
        #expect(EnvironmentVariable.home.value(in: [:], names: Self.names) == nil)
    }

    @Test
    func anOlderHomeDirectoryIsReadWhereTheCurrentOneIsAbsent() throws {
        let home = try TemporaryDirectory.make("migrate-home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".swift-sure"), withIntermediateDirectories: true)
        let environment = ["CFFIXED_USER_HOME": home.path]

        #expect(SiftPaths.home(environment: environment, names: Self.names).lastPathComponent == ".swift-sure")
        #expect(SiftPaths.home(environment: environment, names: [Self.gizmo]).lastPathComponent == ".gizmo")
    }

    @Test
    func theInstallScriptNamesTheCurrentAndLegacyProductNames() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Distribution/install.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        func assigned(_ variable: String) -> String? {
            text.split(separator: "\n").first { $0.hasPrefix(variable + "=") }
                .map { $0.dropFirst(variable.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }

        #expect(assigned("NAME") == ProductName.current.word)
        #expect(assigned("LEGACY_NAMES") == ProductName.legacy.map(\.word).joined(separator: " "))
    }

    @Test
    func theBackupSuffixAndRuleFileNameMatchWhatTheLibraryWrites() {
        let tool = FieldworkTool.sift

        #expect(ProductName.current.backupSuffix == "." + tool.backupExtension)
        #expect(ProductName.current.binary + ".md" == tool.installedRuleName)
    }
}
