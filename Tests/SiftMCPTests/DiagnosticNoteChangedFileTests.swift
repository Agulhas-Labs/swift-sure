//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// The located block quotes the file as it is now; where the file changed after the run that printed the diagnostic, it says so.
@Suite(.temporaryDirectories)
struct DiagnosticNoteChangedFileTests {
    static var diagnostic: String {
        "\(DiagnosticNoteTests.producerPath):6:25: error: binary operator '+' cannot be applied"
    }

    static var notice: String {
        "  Producer.swift changed after this diagnostic; the lines below are the file as it is now"
    }

    /// A `raw:` line naming `log`, as a `swift-sure run` answer ends.
    static func rawLine(_ log: URL) -> String {
        "raw: Orchard @ 0123abc (clean) · \(log.path) (12 lines)"
    }

    /// Writes a log whose modification date is `offset` seconds from now.
    func writeLog(_ name: String, offset: TimeInterval, under folder: String? = nil) throws -> URL {
        var directory = try TemporaryDirectory.make("run-logs")
        if let folder {
            directory = directory.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let log = directory.appendingPathComponent(name)
        try Data("log".utf8).write(to: log)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(offset)], ofItemAtPath: log.path)
        return log
    }

    func context(_ response: (String) throws -> String) throws -> String {
        let repo = try MCPTestRepo.make(declaring: "Depot")
        try MCPTestRepo.add([DiagnosticNoteTests.producerPath: DiagnosticNoteTests.producer], to: repo)
        let marks = try HookMarks(directory: TemporaryDirectory.make("hook-marks"))
        let recorded = RecordedOutput()
        try PostToolUseCommand.answer(to: DiagnosticNoteTests.bash(response(repo.path), cwd: repo.path), output: recorded.output, marks: marks)
        return try DiagnosticNoteTests.context(of: recorded.printed)
    }

    @Test func aFileChangedAfterTheLogIsSaidSoUnderTheHeader() throws {
        let log = try writeLog("run.log", offset: -60)
        let text = try context { _ in [Self.diagnostic, Self.rawLine(log)].joined(separator: "\n") }

        let lines = text.components(separatedBy: "\n")
        let header = try #require(lines.firstIndex { $0.hasPrefix("  \(DiagnosticNoteTests.producerPath):6") })

        #expect(lines[header + 1] == Self.notice)
        #expect(lines[header + 2].contains("| "))
    }

    @Test func aLogUnderAFolderWithSpacesIsStillRead() throws {
        let log = try writeLog("run.log", offset: -60, under: "My Runs · old")
        let text = try context { _ in [Self.diagnostic, Self.rawLine(log)].joined(separator: "\n") }

        #expect(text.contains(Self.notice))
    }

    @Test func aLogNamedRelativeToTheRepositoryIsReadThere() throws {
        let text = try context { repo in
            let logs = URL(fileURLWithPath: repo).appendingPathComponent(".swift-sure/runs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("run.log")
            try Data("log".utf8).write(to: log)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: log.path)
            return [Self.diagnostic, "raw: Orchard @ 0123abc (clean) · .swift-sure/runs/run.log (12 lines)"].joined(separator: "\n")
        }

        #expect(text.contains(Self.notice))
    }

    @Test func aLogNewerThanTheFileAddsNothing() throws {
        let log = try writeLog("run.log", offset: 60)
        let text = try context { _ in [Self.diagnostic, Self.rawLine(log)].joined(separator: "\n") }

        #expect(!text.contains("changed after this diagnostic"))
    }

    @Test func aResponseWithNoRawLineAddsNothing() throws {
        let text = try context { _ in Self.diagnostic }

        #expect(!text.contains("changed after this diagnostic"))
    }

    @Test func aSiteBeforeTheSecondRawLinePairsWithTheSecondLog() throws {
        let older = try writeLog("first.log", offset: 60)
        let newer = try writeLog("second.log", offset: -60)
        let first = "raw: Orchard @ 0123abc (clean) · \(older.path) (3 lines)"
        let text = try context { _ in
            [first, Self.diagnostic, Self.rawLine(newer)].joined(separator: "\n")
        }

        #expect(text.contains(Self.notice))
    }
}
