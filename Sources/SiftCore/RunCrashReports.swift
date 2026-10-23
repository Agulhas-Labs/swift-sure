//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The directory a stopped run looks in for the crash report its test process left, and how its answer shows that directory.
///
/// **Only this run's crash counts.** A report qualifies where it was written since the run started, is a `swiftpm-testing-helper` or `xctest` report, and its `pid` is a test process this run saw or its parent is the command: another session's crash on a shared machine is never named.
public struct RunCrashReports: Sendable {
    /// Where the reports are read from.
    public let directory: URL
    /// The directory as an answer shows it.
    public let shownAs: String

    public init(directory: URL, shownAs: String) {
        self.directory = directory
        self.shownAs = shownAs
    }

    /// The account's own crash reports, shown from `~`.
    public static var live: RunCrashReports {
        RunCrashReports(
            directory: AgentPaths.accountHome.appendingPathComponent("Library/Logs/DiagnosticReports"),
            shownAs: "~/Library/Logs/DiagnosticReports"
        )
    }

    /// The newest report written since `date` by one of `testProcesses` or a test process `parent` started, or `nil` where none qualifies.
    func newest(since date: Date, testProcesses: Set<Int32>, parent: Int32) -> RunCrashReport? {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        let reports = names.filter { $0.hasSuffix(".ips") }.compactMap { name -> RunCrashReport? in
            let url = directory.appendingPathComponent(name)
            guard let written = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, written >= date,
                  let data = manager.contents(atPath: url.path)
            else {
                return nil
            }
            return RunCrashReport.read(data, path: shownAs + "/" + name, written: written, testProcesses: testProcesses, parent: parent)
        }
        return reports.max { ($0.written, $0.path) < ($1.written, $1.path) }
    }
}
