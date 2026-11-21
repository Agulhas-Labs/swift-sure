//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A `raw:` line names its log by an absolute path where `--root` pointed elsewhere, and a site printed by two runs pairs with the later run's log.
@Suite(.temporaryDirectories)
struct DiagnosticNoteAbsoluteLogTests {
    func context(_ response: () throws -> String) throws -> String {
        let repo = try MCPTestRepo.make(declaring: "Depot")
        try MCPTestRepo.add([DiagnosticNoteTests.producerPath: DiagnosticNoteTests.producer], to: repo)
        let marks = try HookMarks(directory: TemporaryDirectory.make("hook-marks"))
        let recorded = RecordedOutput()
        let stdout = try response()
        PostToolUseCommand.answer(to: DiagnosticNoteTests.bash(stdout, cwd: repo.path), output: recorded.output, marks: marks)
        return try DiagnosticNoteTests.context(of: recorded.printed)
    }

    func writeLog(_ name: String, offset: TimeInterval) throws -> URL {
        let log = try TemporaryDirectory.make("run-logs").appendingPathComponent(name)
        try Data("log".utf8).write(to: log)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(offset)], ofItemAtPath: log.path)
        return log
    }

    @Test func anAbsoluteLogPathOutsideTheRepositoryIsReadAsItStands() throws {
        let log = try writeLog("run.log", offset: -60)
        let text = try context { [DiagnosticNoteChangedFileTests.diagnostic, DiagnosticNoteChangedFileTests.rawLine(log)].joined(separator: "\n") }

        #expect(text.contains(DiagnosticNoteChangedFileTests.notice))
    }

    @Test func aRepeatedSitePairsWithTheLastRunsLog() throws {
        let older = try writeLog("first.log", offset: -60)
        let newer = try writeLog("second.log", offset: 60)
        let text = try context {
            [
                DiagnosticNoteChangedFileTests.diagnostic,
                DiagnosticNoteChangedFileTests.rawLine(older),
                DiagnosticNoteChangedFileTests.diagnostic,
                DiagnosticNoteChangedFileTests.rawLine(newer),
            ].joined(separator: "\n")
        }

        #expect(!text.contains("changed after this diagnostic"))
    }
}
