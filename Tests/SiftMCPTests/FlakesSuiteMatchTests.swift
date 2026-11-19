//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Covers `flakes <Suite>` finding Swift Testing failures, which a run records by bare function name: the suite is filed beside the names, read at record time from the index, and matched at query time.
@Suite(.temporaryDirectories)
struct FlakesSuiteMatchTests {
    // MARK: Fixtures

    private static func run(failed: [String], suites: [String: String]? = nil, day: String = "2026-08-20") -> String {
        var object: [String: Any] = [
            "kind": "swift test", "exit": 1, "ms": 100, "ts": "\(day)T10:00:00Z", "root": "/repo/a",
            "tree": "t1", "invocation": "all", "failed": failed, "failed_total": failed.count,
        ]
        if let suites {
            object["failedSuites"] = suites
        }
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private static func writeLog(_ lines: [String]) throws -> URL {
        let file = try TemporaryDirectory.make("flakes-suite").appendingPathComponent("flakes.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func answer(_ query: String, _ lines: [String]) throws -> [String] {
        let file = try writeLog(lines)
        let scope = try LogScope.resolve(nil, inLogsAt: [file]).get()
        let named = RunFailureHistory.named(query, in: RunScan.load(fileURL: file, scope: scope))
        return FlakesQueryAnswer.lines(for: query, in: named, scoped: "") ?? []
    }

    private static let recorded = run(failed: ["testOne()"], suites: ["testOne()": "DepotTests"])

    // MARK: Matching

    @Test
    func aSuiteQueryFindsASwiftTestingFailureRecordedWithItsSuite() throws {
        let lines = try Self.answer("Depot", [Self.recorded])

        #expect(lines.first?.contains("1 test recorded failing") == true)
        #expect(lines.contains("testOne()"))
    }

    @Test
    func aSuiteDotMemberQueryFindsIt() throws {
        let lines = try Self.answer("DepotTests.testOne", [Self.recorded])

        #expect(lines.first?.contains("1 test recorded failing") == true)
    }

    /// A record from before the field existed still matches by its bare name, as it always did.
    @Test
    func anOldRecordWithNoSuiteStillMatchesByBareName() throws {
        let old = Self.run(failed: ["testOne()"])
        let lines = try Self.answer("testOne", [old])

        #expect(lines.first?.contains("1 test recorded failing") == true)
    }

    @Test
    func aSuiteQueryOverAnOldBareRecordSaysItCarriesNoSuite() throws {
        let old = Self.run(failed: ["testOne()"])
        let lines = try Self.answer("Depot", [old])

        #expect(lines.first?.contains("no run recorded a matching test failing") == true)
        #expect(lines.contains("1 test in scope carries no suite (crash records never do; failures recorded before this version, or unresolved) and could not be matched by one"))
    }

    @Test
    func aFunctionQueryDoesNotGetTheSuiteLine() throws {
        let old = Self.run(failed: ["testOne()"])
        let lines = try Self.answer("somethingElse()", [old])

        #expect(!lines.contains { $0.contains("no suite (crash records never do") })
    }

    /// The test's redacted id is a hash of its bare name, so the suite beside it must not move it.
    @Test
    func theRedactedIdIsTheSameWithOrWithoutARecordedSuite() throws {
        let redactor = Redactor(salt: Data("salt".utf8))
        let withSuite = try Self.writeLog([Self.recorded, Self.run(failed: [])])
        let without = try Self.writeLog([Self.run(failed: ["testOne()"]), Self.run(failed: [])])
        let first = RunFailureHistoryReport.render(fileURL: withSuite, redactor: redactor)
        let second = RunFailureHistoryReport.render(fileURL: without, redactor: redactor)

        #expect(first.contains("test-"))
        #expect(first.components(separatedBy: "\n").filter { $0.contains("test-") } == second.components(separatedBy: "\n").filter { $0.contains("test-") })
    }

    // MARK: Record side

    private static var source: String {
        """
        import Testing

        @Suite struct DepotTests {
            @Test func testOne() {
                #expect(true)
            }
        }

        struct Outer {
            @Suite struct Inner {
                @Test func nestedCall() {
                    #expect(true)
                }
            }
        }
        """
    }

    /// A git checkout holding `files`, indexed through the engine so the store is the one a run would find.
    static func indexedRepository(files: [String: String]) async throws -> URL {
        let root = try TemporaryDirectory.make("flakes-suite-repo").resolvingSymlinksInPath()
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["HOME"] = root.path
        for arguments in [["init", "-b", "main"], ["add", "-A"], ["-c", "user.email=t@example.com", "-c", "user.name=Tester", "commit", "-m", "fixture"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = root
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        _ = try await SiftEngine(directory: root).ensureFresh()
        return root
    }

    private static func recordedEntry(for failures: [RunTestFailure], in root: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let file = try TemporaryDirectory.make("flakes-suite-log").appendingPathComponent("run.jsonl")
        let names = failures.map(\.name)
        RunUsageLog(fileURL: file).record(
            logKey: "swift test",
            exitCode: 1,
            answer: RunUsageLog.Answer(failedTests: names, failures: failures),
            repositoryRoot: root,
            milliseconds: 1
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first, sourceLocation: sourceLocation)
        return try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], sourceLocation: sourceLocation)
    }

    @Test
    func aFailureWithALocationRecordsItsSuiteFromTheIndex() async throws {
        let root = try await Self.indexedRepository(files: ["Tests/GizmoTests/DepotTests.swift": Self.source])
        let entry = try Self.recordedEntry(for: [
            RunTestFailure(name: "testOne()", location: "DepotTests.swift:5:9", message: "x"),
            RunTestFailure(name: "nestedCall()", location: "DepotTests.swift:12:13", message: "x"),
            RunTestFailure(name: "unlocated()", location: nil, message: "x"),
        ], in: root)
        let suites = try #require(entry["failedSuites"] as? [String: String])

        #expect(suites == ["testOne()": "DepotTests", "nestedCall()": "Outer/Inner"])
        // The names themselves are untouched.
        #expect((entry["failed"] as? [String])?.contains("testOne()") == true)
    }

    @Test
    func aFileNameMoreThanOneIndexedFileCarriesStaysBare() async throws {
        let root = try await Self.indexedRepository(files: [
            "Tests/GizmoTests/DepotTests.swift": Self.source,
            "Tests/DepotKitTests/DepotTests.swift": Self.source,
        ])
        let entry = try Self.recordedEntry(for: [
            RunTestFailure(name: "testOne()", location: "DepotTests.swift:5:9", message: "x"),
        ], in: root)

        #expect(entry["failedSuites"] == nil)
        #expect((entry["failed"] as? [String]) == ["testOne()"])
    }

    private static var helperSource: String {
        """
        import Testing

        struct Fixture {
            static func check() {
                #expect(true)
            }
        }

        @Suite struct HelperTests {
            @Test func testOne() {
                Fixture.check()
            }
        }
        """
    }

    /// An `#expect` inside a helper another test calls sits in the helper's type, which is not the failing test's suite.
    @Test
    func aFailureInsideAHelperRecordsNoSuiteButADirectOneDoes() async throws {
        let root = try await Self.indexedRepository(files: ["Tests/GizmoTests/HelperTests.swift": Self.helperSource])
        let viaHelper = try Self.recordedEntry(for: [
            RunTestFailure(name: "testOne()", location: "HelperTests.swift:5:9", message: "x"),
        ], in: root)
        let direct = try Self.recordedEntry(for: [
            RunTestFailure(name: "testOne()", location: "HelperTests.swift:11:9", message: "x"),
        ], in: root)

        #expect(viaHelper["failedSuites"] == nil)
        #expect((direct["failedSuites"] as? [String: String]) == ["testOne()": "HelperTests"])
    }

    private static var secondSource: String {
        """
        import Testing

        @Suite struct AlphaTests {
            @Test func check() {
                #expect(true)
            }
        }
        """
    }

    private static var thirdSource: String {
        """
        import Testing

        @Suite struct BetaTests {
            @Test func check() {
                #expect(true)
            }
        }
        """
    }

    /// One bare name failing in two suites cannot carry either: recording the first would hide the other from `flakes <Suite>`.
    @Test
    func aNameFailingInTwoSuitesRecordsNoSuiteButOneLocatedFailureDoes() async throws {
        let root = try await Self.indexedRepository(files: [
            "Tests/GizmoTests/AlphaTests.swift": Self.secondSource,
            "Tests/GizmoTests/BetaTests.swift": Self.thirdSource,
        ])
        let both = try Self.recordedEntry(for: [
            RunTestFailure(name: "check()", location: "AlphaTests.swift:5:9", message: "x"),
            RunTestFailure(name: "check()", location: "BetaTests.swift:5:9", message: "x"),
        ], in: root)
        let one = try Self.recordedEntry(for: [
            RunTestFailure(name: "check()", location: "AlphaTests.swift:5:9", message: "x"),
        ], in: root)

        #expect(both["failedSuites"] == nil)
        #expect((one["failedSuites"] as? [String: String]) == ["check()": "AlphaTests"])
    }

    /// Sets an index's schema version to a value no build writes, and reads back what is stored.
    static func sqlite(_ statement: String, in root: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [SiftPaths.cache(in: root).appendingPathComponent(SiftPaths.indexFileName).path, statement]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Recording a failure must not drop and rebuild an index written at another schema version.
    @Test
    func aStoreAtAnotherSchemaVersionIsLeftUntouchedAndTheFailureRecordedBare() async throws {
        let root = try await Self.indexedRepository(files: ["Tests/GizmoTests/DepotTests.swift": Self.source])
        _ = try Self.sqlite("PRAGMA user_version=9999;", in: root)
        let tables = try Self.sqlite("SELECT count(*) FROM sqlite_master WHERE type='table';", in: root)
        let entry = try Self.recordedEntry(for: [
            RunTestFailure(name: "testOne()", location: "DepotTests.swift:5:9", message: "x"),
        ], in: root)

        #expect(entry["failedSuites"] == nil)
        #expect((entry["failed"] as? [String]) == ["testOne()"])
        #expect(try Self.sqlite("PRAGMA user_version;", in: root) == "9999")
        #expect(try Self.sqlite("SELECT count(*) FROM sqlite_master WHERE type='table';", in: root) == tables)
        #expect(Int(tables) ?? 0 > 1)
    }

    @Test
    func aLowercaseWordQueryGetsNoSuiteLine() throws {
        let old = Self.run(failed: ["testOne()"])

        #expect(try !Self.answer("somethingElse", [old]).contains { $0.contains("no suite (crash records never do") })
        #expect(try Self.answer("Depot", [old]).contains { $0.contains("no suite (crash records never do") })
        #expect(try Self.answer("depot.testOne", [old]).contains { $0.contains("no suite (crash records never do") })
    }

    @Test
    func aRepositoryWithNoIndexRecordsNoSuites() throws {
        let root = try TemporaryDirectory.make("flakes-suite-bare")
        let entry = try Self.recordedEntry(for: [
            RunTestFailure(name: "testOne()", location: "DepotTests.swift:5:9", message: "x"),
        ], in: root)

        #expect(entry["failedSuites"] == nil)
    }
}
