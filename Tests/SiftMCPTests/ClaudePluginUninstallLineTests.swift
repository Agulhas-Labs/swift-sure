//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// `swift-sure uninstall` leaves an enabled plugin in place and names the command that removes it.
@Suite(.temporaryDirectories)
struct ClaudePluginUninstallLineTests {
    private static var pluginLine: String {
        "plugin: swift-sure@gizmo-market is enabled and left in place; claude plugin uninstall swift-sure@gizmo-market removes it"
    }

    @Test(arguments: [[String](), ["--purge"], ["--settings", "elsewhere.json"]])
    func anEnabledPluginIsNamedWhateverTheOptions(arguments: [String]) throws {
        let installed = try UninstallCommandTests.install()
        try ClaudePluginInstallSkipTests.enable(["swift-sure@gizmo-market"], home: installed.home)
        let arguments = arguments.map { $0 == "elsewhere.json" ? installed.home.appendingPathComponent($0).path : $0 }

        let lines = try UninstallCommandTests.uninstall(installed, arguments, remover: UninstallCommandTests.ServerRemover())

        #expect(lines.filter { $0.hasPrefix("plugin:") } == [Self.pluginLine], "\(lines)")
    }

    @Test
    func theBinaryLineIsStillTheLastWithThePluginEnabled() throws {
        let installed = try UninstallCommandTests.install()
        try ClaudePluginInstallSkipTests.enable(["swift-sure@gizmo-market"], home: installed.home)

        let lines = try UninstallCommandTests.uninstall(installed, remover: UninstallCommandTests.ServerRemover())

        #expect(lines.last?.hasPrefix("binary:") == true, "\(lines)")
        #expect(lines.contains(Self.pluginLine), "\(lines)")
    }

    @Test
    func withoutThePluginNoPluginLineIsPrinted() throws {
        let installed = try UninstallCommandTests.install()

        let lines = try UninstallCommandTests.uninstall(installed, remover: UninstallCommandTests.ServerRemover())

        #expect(!lines.contains { $0.hasPrefix("plugin:") }, "\(lines)")
    }
}
