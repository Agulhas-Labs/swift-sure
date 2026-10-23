//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftMCP
import Testing

/// The transcript scan keys a Bash `swift-sure digest` by the repository it ran in exactly as the advice hook's ledger does, so `audit` credits the same digests the hook let a later read through for.
@Suite(.temporaryDirectories) struct ShellDigestScanAgreementTests {
    /// Lines with several moves, a move per statement, a move the hook cannot follow, and none at all, each run from the second with `{ONE}` and `{TWO}` spelling the two repositories: the scan holds each target under the repository the ledger records it at, or nowhere where the ledger records it nowhere.
    @Test(arguments: [
        "cd {TWO} && cd {ONE} && swift-sure digest Alpha",
        "cd / && cd {TWO} && git status && swift-sure digest Beta",
        "cd {TWO} && swift-sure digest Beta; cd {ONE} && swift-sure digest Alpha",
        "cd {ONE} && swift-sure digest Alpha; cd {TWO} && swift-sure digest --root {ONE} Alpha",
        "(cd {TWO} && swift-sure digest Beta)",
        "pushd {TWO} && swift-sure digest Beta",
        "cd {TWO} || true && swift-sure digest Beta",
        "swift-sure digest Alpha | head -40",
    ])
    func theScanKeysAShellDigestWhereTheLedgerDoes(line: String) throws {
        let one = try MCPTestRepo.make(declaring: "Alpha")
        let two = try MCPTestRepo.make(declaring: "Beta")
        let command = line.replacingOccurrences(of: "{ONE}", with: one.path).replacingOccurrences(of: "{TWO}", with: two.path)

        let ledger = PreToolUseCommand.digestsAsked(toolName: "Bash", input: ["command": command], cwd: two.path).mapValues(Set.init)
        var state = TranscriptScanState()
        state.holdShellDigests(of: command, block: ["id": "t1"], directory: two.path)

        #expect(state.pendingShellDigests["t1"] ?? [:] == ledger)
        state.creditShellDigests(answering: "t1", block: ["id": "t1"], failed: false)
        #expect(Set(state.digests.keys) == Set(ledger.keys))
    }
}
