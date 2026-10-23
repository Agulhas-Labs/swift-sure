//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// Covers that the binary `install-hook` registers is the current name's sibling when it ran through an alias link, with an alias stood in (`gizmo-alias`).
@Suite(.temporaryDirectories)
struct InstallHookAliasBinaryPathTests {
    @Test
    func anAliasRegistersTheCurrentSiblingBesideIt() throws {
        let scratch = try TemporaryDirectory.make("install-path-alias")
        let alias = try InstallHookBinaryPathTests.executable(at: "bin/gizmo-alias", in: scratch)
        let sibling = try InstallHookBinaryPathTests.executable(at: "bin/swift-sure", in: scratch)
        let environment = ["PATH": "\(scratch.path)/empty", "CFFIXED_USER_HOME": scratch.path]

        let path = InstallHookCommand.binaryPath(invokedAs: alias.path, environment: environment, executable: alias.path, aliases: ["gizmo-alias"])

        #expect(path == sibling.path)
    }

    @Test
    func aNameThatIsNeitherLegacyNorAliasIsRegisteredAsItIs() throws {
        let scratch = try TemporaryDirectory.make("install-path-not-alias")
        let other = try InstallHookBinaryPathTests.executable(at: "bin/gizmo-alias", in: scratch)
        try InstallHookBinaryPathTests.executable(at: "bin/swift-sure", in: scratch)
        let environment = ["PATH": "\(scratch.path)/empty", "CFFIXED_USER_HOME": scratch.path]

        let path = InstallHookCommand.binaryPath(invokedAs: other.path, environment: environment, executable: other.path, aliases: [])

        #expect(path == other.path)
    }
}
