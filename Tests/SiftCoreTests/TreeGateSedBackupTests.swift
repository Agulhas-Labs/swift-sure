//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the tree gate's refusal of the backup file BSD `sed -i -E` leaves beside the file it edited.
@Suite(.temporaryDirectories)
struct TreeGateSedBackupTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // SiftCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository root

    private static let carried = [
        "Distribution/verify-private.sh", "Distribution/private-terms.txt", "Distribution/verify-tree.sh",
    ]

    /// A tracked file whose name is another tracked file's name plus the flag is a leftover, and the gate says which.
    @Test
    func aTrackedBackupBesideItsStemIsRefused() throws {
        let root = try TemporaryDirectory.make("tree-gate-sed").appending(path: "tree-gate-sed")
        defer { try? FileManager.default.removeItem(at: root) }
        let subject = try Self.gitCheckout(in: root)
        try TestSources.write("nothing private here.\n", to: "CHANGELOG.md", in: subject)
        try TestSources.write("nothing private here.\n", to: "CHANGELOG.md-E", in: subject)
        try TestSources.commitAll(in: subject, message: "a backup sed left behind")

        let run = try Self.gate(in: subject, root: root)
        // Reduced to a `Bool` before it is asserted on: the sub-expression is a whole run's output.
        let saidWhy = run.output.contains("error: CHANGELOG.md-E is the backup BSD sed -i -E writes beside CHANGELOG.md; delete it")

        #expect(run.status == 1, "the tree gate passed a sed backup:\n\(run.output)")
        #expect(saidWhy, "the tree gate refused without naming the backup:\n\(run.output)")
    }

    /// A path that merely ends in the flag, with no stem tracked beside it, is an ordinary file.
    @Test
    func aPathEndingInTheFlagWithNoStemIsNotRefused() throws {
        let root = try TemporaryDirectory.make("tree-gate-sed").appending(path: "tree-gate-sed")
        defer { try? FileManager.default.removeItem(at: root) }
        let subject = try Self.gitCheckout(in: root)
        try TestSources.write("nothing private here.\n", to: "Gizmo-E", in: subject)
        try TestSources.commitAll(in: subject, message: "a file that only looks like a backup")

        let run = try Self.gate(in: subject, root: root)
        let refusedAsBackup = run.output.contains("sed -i -E")

        #expect(!refusedAsBackup, "the tree gate took a lone file for a sed backup:\n\(run.output)")
        #expect(run.status == 0, "the tree gate refused a clean tree:\n\(run.output)")
    }
}

extension TreeGateSedBackupTests {
    /// A committed checkout with one neighbour beside it, carrying the tree gate and what it execs.
    private static func gitCheckout(in root: URL) throws -> URL {
        let subject = root.appending(path: "Parent/Subject")
        try FileManager.default.createDirectory(at: subject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Parent/Kestrel"), withIntermediateDirectories: true)
        for file in carried {
            let destination = subject.appending(path: file)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: repository.appending(path: file), to: destination)
        }
        try TestSources.runGit(["init", "-b", "main"], in: subject)
        try TestSources.runGit(["config", "user.email", "tester@example.invalid"], in: subject)
        try TestSources.runGit(["config", "user.name", "Tester"], in: subject)
        try TestSources.commitAll(in: subject, message: "seed")

        return subject
    }

    /// Runs the tree gate in the checkout, with no `GIT_*` variable and a home of the test's own.
    private static func gate(in subject: URL, root: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [subject.appending(path: "Distribution/verify-tree.sh").path]
        process.currentDirectoryURL = subject
        var environment = ProcessEnvironment.withoutGit()
        environment["HOME"] = root.path
        environment["CFFIXED_USER_HOME"] = root.path
        process.environment = environment
        let sink = Pipe()
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        let output = sink.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(data: output, encoding: .utf8) ?? "")
    }
}
