//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `run --without` in a tree nobody may write refuses in one line of its own, where it ended in the platform's words about a file it never needed to name.
@Suite(.temporaryDirectories)
struct ReadOnlyWriteCommandTests {
    @Test
    func runWithoutRefusesBeforeItLooksForASetAsideStoreItCannotMake() throws {
        let repository = try MCPTestRepo.make()
        try Self.chmod("a-w", repository)
        defer { try? Self.chmod("a+w", repository) }
        let command = RunWithoutCommand(
            arguments: ["swift", "test", "--filter", "Depot"],
            pathspecs: ["Sources"],
            line: nil,
            since: nil,
            runKey: { _ in nil },
            file: { _, _, _, _ in }
        )

        let refusal = #expect(throws: EngineError.self) {
            try TreeWritability.requireSetAsideStore(repoRoot: repository)
        }
        let exit = #expect(throws: ExitCode.self) {
            try command.run(in: repository)
        }

        #expect(refusal.map(String.init(describing:))?.contains("cannot be written, so there is nowhere to set the change aside") == true)
        #expect(exit?.rawValue == RunWithoutCommand.Exit.refused.rawValue)
        #expect(!FileManager.default.fileExists(atPath: SiftPaths.cache(in: repository).path))
    }

    /// `chmod -R <mode>` over `root`.
    private static func chmod(_ mode: String, _ root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["-R", mode, root.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
