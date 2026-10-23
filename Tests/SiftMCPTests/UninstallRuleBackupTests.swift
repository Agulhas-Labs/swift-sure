//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import Testing

/// `swift-sure uninstall` takes out the `swift-sure.md.bak-swift-sure` copy `swift-sure install` keeps beside a rule it replaced, and leaves a symlink at that path where it is.
@Suite(.temporaryDirectories)
struct UninstallRuleBackupTests {
    private typealias Fixture = UninstallCommandTests

    @Test
    func theRuleBackupGoesWithTheRule() throws {
        let installed = try Fixture.install()
        let backup = SettingsBackupFile.url(beside: installed.rule, tool: .sift)
        try "the rule before swift-sure replaced it".write(to: backup, atomically: true, encoding: .utf8)

        let lines = try Fixture.uninstall(installed, remover: Fixture.ServerRemover())

        #expect(PathKind.of(backup) == .absent)
        #expect(PathKind.of(installed.rule) == .absent)
        #expect(lines.contains("rule: removed \(backup.path)"))
        #expect(FileManager.default.fileExists(atPath: installed.rule.deletingLastPathComponent().appendingPathComponent("other.md").path))
    }

    @Test
    func aRuleBackupThatIsASymlinkIsLeftWhereItIs() throws {
        let installed = try Fixture.install()
        let backup = SettingsBackupFile.url(beside: installed.rule, tool: .sift)
        let elsewhere = installed.home.appendingPathComponent("elsewhere.md")
        try "kept".write(to: elsewhere, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: backup.path, withDestinationPath: elsewhere.path)

        let lines = try Fixture.uninstall(installed, remover: Fixture.ServerRemover())

        #expect(PathKind.of(backup) == .symlink(elsewhere.path))
        #expect(lines.contains("rule: \(backup.path) is a symlink to \(elsewhere.path) — left as is"))
    }
}
