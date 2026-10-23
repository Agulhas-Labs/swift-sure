//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers which crash report a stopped run names and what it reads from it, from reports written into a directory of the test's own.
@Suite(.temporaryDirectories)
struct RunCrashReportsTests {
    private static let since = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let parent: Int32 = 70469
    private static let helper: Int32 = 70928

    /// The newest report this run's test process left is named with its exception, its signal and the recursion depth its crashed thread records, not one another thread records.
    @Test
    func theVerdictNamesTheCrashReportAndItsRecursionDepth() throws {
        let directory = try TemporaryDirectory.make("run-crash-reports-depth")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.write("swiftpm-testing-helper-2026-10-20-092000.ips", in: directory, at: Self.since.addingTimeInterval(5), pid: Self.helper, crashedDepth: 40)
        try Self.write("swiftpm-testing-helper-2026-10-20-092101.ips", in: directory, at: Self.since.addingTimeInterval(9), pid: Self.helper, crashedDepth: 6326)

        let report = RunCrashReports(directory: directory, shownAs: "~/Library/Logs/DiagnosticReports")
            .newest(since: Self.since, testProcesses: [Self.helper], parent: 1)

        #expect(report?.line == "crash report: ~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-10-20-092101.ips — EXC_BAD_ACCESS (SIGBUS), recursion depth 6326")
        #expect(RunStoppedTest(quiet: 30, crash: report).lines == [
            "✘ swift test did not exit 30 s after its test process ended; stopped it",
            "crash report: ~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-10-20-092101.ips — EXC_BAD_ACCESS (SIGBUS), recursion depth 6326",
        ])
    }

    /// A report whose parent is the command qualifies though its pid was never seen, and one with no recursion record carries no depth.
    @Test
    func aReportFromTheCommandsChildWithoutRecursionCarriesNoDepth() throws {
        let directory = try TemporaryDirectory.make("run-crash-reports-parent")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.write("xctest-2026-10-20-092101.ips", in: directory, at: Self.since.addingTimeInterval(1), name: "xctest", pid: 5, parent: Self.parent, crashedDepth: nil)

        let report = RunCrashReports(directory: directory, shownAs: "~/r").newest(since: Self.since, testProcesses: [], parent: Self.parent)

        #expect(report?.line == "crash report: ~/r/xctest-2026-10-20-092101.ips — EXC_BAD_ACCESS (SIGBUS)")
    }

    /// Another session's crash, a report from before the run and a report for a process that is not a test process are never named.
    @Test
    func onlyThisRunsTestProcessCrashIsNamed() throws {
        let directory = try TemporaryDirectory.make("run-crash-reports-others")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.write("swiftpm-testing-helper-2026-10-20-090000.ips", in: directory, at: Self.since.addingTimeInterval(1), pid: 999, parent: 998, crashedDepth: 10)
        try Self.write("swiftpm-testing-helper-2026-10-20-080000.ips", in: directory, at: Self.since.addingTimeInterval(-60), pid: Self.helper, crashedDepth: 10)
        try Self.write("Finder-2026-10-20-090000.ips", in: directory, at: Self.since.addingTimeInterval(1), name: "Finder", pid: Self.helper, crashedDepth: 10)

        let report = RunCrashReports(directory: directory, shownAs: "~").newest(since: Self.since, testProcesses: [Self.helper], parent: Self.parent)

        #expect(report == nil)
    }

    /// Writes a report shaped as the system writes one: a header line, then a body whose crashed thread lists a few frames and records the real count and the recursion apart from them, beside another thread with a recursion of its own.
    private static func write(_ file: String, in directory: URL, at written: Date, name: String = "swiftpm-testing-helper", pid: Int32, parent: Int32 = 1, crashedDepth: Int?) throws {
        let header: [String: Any] = ["app_name": name, "name": name, "bug_type": "309"]
        var crashed: [String: Any] = ["triggered": true, "frames": Array(repeating: ["symbol": "frame"], count: 56)]
        if let crashedDepth {
            crashed["originalLength"] = crashedDepth * 2 + 44
            crashed["recursionInfoArray"] = [["depth": crashedDepth]]
        }
        let other: [String: Any] = ["recursionInfoArray": [["depth": 99999]], "frames": [["symbol": "other"]]]
        let body: [String: Any] = [
            "pid": pid, "parentPid": parent, "procName": name, "faultingThread": 1,
            "exception": ["type": "EXC_BAD_ACCESS", "signal": "SIGBUS"],
            "threads": [other, crashed],
        ]
        var data = try JSONSerialization.data(withJSONObject: header)
        data.append(UInt8(ascii: "\n"))
        try data.append(JSONSerialization.data(withJSONObject: body))
        let url = directory.appendingPathComponent(file)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: url.path)
    }
}
