//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
@testable import SiftMCP
import Testing

private typealias Fixture = UninstallCommandTests

@Suite(.temporaryDirectories)
struct UninstallRuleDirectoryTests {
    /// A directory at the rule's path is listed and left, as the dry run says, never deleted with what is inside it.
    @Test
    func aDirectoryAtTheRulePathIsLeftAndReported() throws {
        let installed = try Fixture.install()
        try FileManager.default.removeItem(at: installed.rule)
        try FileManager.default.createDirectory(at: installed.rule, withIntermediateDirectories: true)
        let inside = installed.rule.appendingPathComponent("keep.txt")
        try "mine".write(to: inside, atomically: true, encoding: .utf8)

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], remover: Fixture.ServerRemover())

        #expect(status == 1)
        #expect(lines.contains("rule: not removed — \(installed.rule.path) is not a plain file"), "\(lines)")
        #expect(FileManager.default.fileExists(atPath: inside.path))
    }
}
