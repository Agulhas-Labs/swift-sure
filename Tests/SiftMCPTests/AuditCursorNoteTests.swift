//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// Where SwiftSure's hooks are registered with Cursor, `audit` ends its answer by saying Cursor's sessions were not read; where they are not, it says nothing of Cursor.
@Suite(.temporaryDirectories)
struct AuditCursorNoteTests {
    /// SwiftSure's entries in the Cursor directory put the line last, naming the directory scanned.
    @Test func aCursorWithSiftsHooksGetsTheLineLast() throws {
        let projects = try Self.projects()
        let cursor = try Self.cursorDirectory(hooks: Self.siftHooks())

        let lines = Self.audit(projects, cursor: cursor).components(separatedBy: "\n")

        #expect(lines.last == "not read: Cursor's sessions — swift-sure audit reads Claude Code's transcripts (\(Redactor.tilded(projects.path))) only", "\(lines)")
        #expect(lines.filter { $0.hasPrefix("not read: Cursor's sessions") }.count == 1, "\(lines)")
    }

    /// A hooks.json holding only another tool's hooks says nothing.
    @Test func aCursorWithOnlyAnotherToolsHooksGetsNoLine() throws {
        let other = Data(#"{"version":1,"hooks":{"stop":[{"command":"/usr/local/bin/gizmo hook stop"}]}}"#.utf8)
        let cursor = try Self.cursorDirectory(hooks: other)

        let text = try Self.audit(Self.projects(), cursor: cursor)

        #expect(!text.contains("not read:"), "\(text)")
    }

    /// A machine with no Cursor directory, or a hooks.json that does not parse, says nothing.
    @Test func noCursorDirectoryOrAnUnreadableFileGetsNoLine() throws {
        let projects = try Self.projects()
        let missing = try TemporaryDirectory.make("cursor").appendingPathComponent("absent")
        let broken = try Self.cursorDirectory(hooks: Data("{ not json".utf8))

        #expect(!Self.audit(projects, cursor: missing).contains("not read:"))
        #expect(!Self.audit(projects, cursor: broken).contains("not read:"))
        #expect(!Self.audit(projects, cursor: nil).contains("not read:"))
    }

    /// With no transcripts at all, the "none found" answer is followed by the line.
    @Test func theNoTranscriptsAnswerIsFollowedByTheLine() throws {
        let empty = try TemporaryDirectory.make("projects").appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let cursor = try Self.cursorDirectory(hooks: Self.siftHooks())

        let lines = Self.audit(empty, cursor: cursor).components(separatedBy: "\n")

        #expect(lines.first?.hasPrefix("no session transcripts found") == true, "\(lines)")
        #expect(lines.last?.hasPrefix("not read: Cursor's sessions — swift-sure audit reads Claude Code's transcripts (") == true, "\(lines)")
        #expect(lines.count == 2, "\(lines)")
    }

    /// `--share` prints two lines and nothing else, Cursor installed or not.
    @Test func shareIsTheSameTwoLinesWithCursorInstalled() throws {
        let projects = try Self.projects()
        let cursor = try Self.cursorDirectory(hooks: Self.siftHooks())

        let with = Self.audit(projects, cursor: cursor, shareOnly: true)
        let without = Self.audit(projects, cursor: nil, shareOnly: true)

        #expect(with == without, "\(with)")
        #expect(!with.contains("not read:"), "\(with)")
        #expect(with.components(separatedBy: "\n").count == 2, "\(with)")
    }

    /// A replay summary ends on the note, after the elapsed line.
    @Test func aReplaySummaryEndsOnTheLineAfterTheElapsedLine() async throws {
        let projects = try Self.projects()
        let transcript = try #require(FileManager.default.enumerator(at: projects, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.first { $0.pathExtension == "jsonl" })
        let cursor = try Self.cursorDirectory(hooks: Self.siftHooks())
        let scratch = try TemporaryDirectory.make("replay")
        let snapshot = TranscriptSnapshot.take(projectsDirectory: projects, since: nil, transcript: transcript.path)
        defer { snapshot.indexes.close() }

        let report = await InPlaceAnswerTests.onItsOwnThread {
            AuditCommand.report(
                snapshot: snapshot,
                projectsDirectory: projects,
                since: nil,
                transcript: transcript.path,
                replay: true,
                scratch: scratch,
                timeBudget: InPlaceAnswerTests.roomy,
                summary: true,
                cursorDirectory: cursor,
                started: Date()
            ).report
        }
        let lines = report.components(separatedBy: "\n")

        #expect(lines.last?.hasPrefix("not read: Cursor's sessions") == true, "\(lines)")
        #expect(lines.dropLast().last?.hasPrefix("elapsed ") == true, "\(lines)")
    }

    /// The elapsed line is read after the replay, so it covers the time the run took.
    @Test func theElapsedLineCoversTheReplay() async throws {
        let projects = try Self.projects()
        let transcript = try #require(FileManager.default.enumerator(at: projects, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.first { $0.pathExtension == "jsonl" })
        let scratch = try TemporaryDirectory.make("replay")
        let snapshot = TranscriptSnapshot.take(projectsDirectory: projects, since: nil, transcript: transcript.path)
        defer { snapshot.indexes.close() }
        let slept = SleptOnce()

        let report = await InPlaceAnswerTests.onItsOwnThread {
            AuditCommand.report(
                snapshot: snapshot,
                projectsDirectory: projects,
                since: nil,
                transcript: transcript.path,
                replay: true,
                scratch: scratch,
                timeBudget: InPlaceAnswerTests.roomy,
                summary: true,
                cursorDirectory: nil,
                started: Date(),
                progress: { _ in
                    if slept.first() {
                        Thread.sleep(forTimeInterval: 1.2)
                    }
                }
            ).report
        }

        let line = try #require(report.components(separatedBy: "\n").last { $0.hasPrefix("elapsed ") }, "\(report)")
        let seconds = line.dropFirst("elapsed ".count).split(separator: " ").reduce(0) { total, part in
            let number = Int(part.dropLast()) ?? 0
            return switch part.last {
            case "h": total + number * 3600
            case "m": total + number * 60
            default: total + number
            }
        }

        #expect(seconds >= 1, "\(line)")
    }
}

private extension AuditCursorNoteTests {
    /// True once, for the first caller.
    final class SleptOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func first() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            defer { done = true }
            return !done
        }
    }

    /// The plain audit of everything under `projects`, with `cursor` as the Cursor directory.
    static func audit(_ projects: URL, cursor: URL?, shareOnly: Bool = false) -> String {
        let snapshot = TranscriptSnapshot.take(projectsDirectory: projects, since: nil, transcript: nil)
        defer { snapshot.indexes.close() }
        return AuditCommand.report(snapshot: snapshot, projectsDirectory: projects, since: nil, shareOnly: shareOnly, cursorDirectory: cursor).report
    }

    /// A hooks.json as the installer writes it.
    static func siftHooks() throws -> Data {
        try SiftCursorSetup.hooks.apply(to: nil, binaryWord: "/opt/gizmo/bin/swift-sure").data
    }

    /// A Cursor directory holding `hooks` as its hooks.json.
    static func cursorDirectory(hooks: Data) throws -> URL {
        let directory = try TemporaryDirectory.make("cursor").appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try hooks.write(to: directory.appendingPathComponent(CursorHooksFile.fileName))
        return directory
    }

    /// A projects directory with one session holding one cold lookup.
    static func projects() throws -> URL {
        let root = try TemporaryDirectory.make("projects").appendingPathComponent("projects")
        let project = root.appendingPathComponent("-Users-someone-Developer-Depot")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let cwd = try TemporaryDirectory.make("repo")
        let lines = try [
            TranscriptAuditReplayTests.call("cat Sources/Depot/Widget.swift", id: "c1", cwd: cwd.path, at: "2026-09-21T10:00:00Z"),
            TranscriptFixture.toolResult(id: "c1", isError: false, text: "struct Widget"),
        ]
        try Data(lines.joined(separator: [0x0A]) + [0x0A]).write(to: project.appendingPathComponent("11112221-3333.jsonl"))
        return root
    }
}
