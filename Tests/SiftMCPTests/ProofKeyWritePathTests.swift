//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// The proof key is applied where the run files its records, not only where a test seeds them: a red run spelled with a build location revokes the green of the plain command.
@Suite(.temporaryDirectories)
struct ProofKeyWritePathTests {
    @Test
    func aRedRunWithAScratchPathDropsTheGreenOfThePlainCommand() throws {
        let repository = try TemporaryDirectory.make("proof-key-write-path").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Self.initialiseRepository(repository)
        let tree = try #require(TreeKey.of(repositoryRoot: repository))
        let toolchain = try #require(ToolchainIdentity.current())
        let ran = RunCommand.ProvableRun(tree: tree, workingDirectory: ".")
        let outcome = { (exitCode: Int32) in
            RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: exitCode, report: nil, log: nil, repositoryRoot: repository)
        }
        var green = try RunCommand.parse(["--", "swift", "test"])
        green.writesUnder = repository
        var red = try RunCommand.parse(["--", "swift", "test", "--scratch-path", "/tmp/x"])
        red.writesUnder = repository
        let ledger = RunLedger.inRepository(at: repository)

        ledger.recordGreen(green.ledgerRecord(outcome(0), ran: ran, in: repository, toolchain: toolchain.description, milliseconds: 1))
        #expect(ledger.records().map(\.command) == ["swift test"])

        red.recordFailure(outcome(1), ran: ran, in: repository, milliseconds: 1)

        #expect(ledger.records().isEmpty)
        #expect(ledger.failedRuns.records().map(\.command) == ["swift test"])
    }
}

private extension ProofKeyWritePathTests {
    static func initialiseRepository(_ root: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "struct Gizmo {}\n".write(to: root.appendingPathComponent("Sources/Gizmo.swift"), atomically: true, encoding: .utf8)
        for arguments in [["init", "-q", "-b", "main"], ["add", "-A"], ["-c", "user.email=t@example.com", "-c", "user.name=T", "commit", "-q", "-m", "seed"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.environment = ProcessEnvironment.withoutGit()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, sourceLocation: sourceLocation)
        }
    }
}
