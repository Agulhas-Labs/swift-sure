//
// Copyright © Agulhas Labs
//

import Foundation

/// A crash report a run's test process left, as the line of a stopped run names it.
///
/// **Read for its recursion, not only its top frame.** A stack overflow lists a few dozen frames and records the crashed thread's real frame count apart from them, with the recursion's depth in a recursion record, so reading the listed frames alone names the wrong function.
public struct RunCrashReport: Sendable, Equatable {
    /// The report's path as the line shows it.
    public let path: String
    /// The exception type the report records, such as `EXC_BAD_ACCESS`.
    public let exceptionType: String
    /// The signal the report records, such as `SIGBUS`, or `nil` where it records none.
    public let signal: String?
    /// The deepest recursion the crashed thread's recursion record carries, or `nil` where it carries none.
    public let recursionDepth: Int?
    /// When the report was written, which orders several that qualify.
    let written: Date

    public init(path: String, exceptionType: String, signal: String?, recursionDepth: Int?, written: Date = .distantPast) {
        self.path = path
        self.exceptionType = exceptionType
        self.signal = signal
        self.recursionDepth = recursionDepth
        self.written = written
    }

    /// The one line a stopped run prints about it.
    public var line: String {
        let kind = signal.map { "\(exceptionType) (\($0))" } ?? exceptionType
        let depth = recursionDepth.map { ", recursion depth \($0)" } ?? ""
        return "crash report: \(path) — \(kind)\(depth)"
    }

    /// The report in `data` — a header line, then the body — where it is a test process's and was written by one of `testProcesses` or a child of `parent`; `nil` for any other.
    static func read(_ data: Data, path: String, written: Date, testProcesses: Set<Int32>, parent: Int32) -> RunCrashReport? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let header = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...]) as? [String: Any]
        else {
            return nil
        }
        let name = header["name"] as? String ?? header["app_name"] as? String ?? body["procName"] as? String
        guard name == "swiftpm-testing-helper" || name == "xctest" else {
            return nil
        }
        let pid = (body["pid"] as? NSNumber)?.int32Value
        let parentPid = (body["parentPid"] as? NSNumber)?.int32Value
        guard pid.map(testProcesses.contains) == true || parentPid == parent else {
            return nil
        }
        let exception = body["exception"] as? [String: Any]
        return RunCrashReport(
            path: path,
            exceptionType: exception?["type"] as? String ?? "unknown exception",
            signal: exception?["signal"] as? String,
            recursionDepth: crashedThread(of: body).flatMap(recursionDepth(of:)),
            written: written
        )
    }

    /// The thread the report says crashed: the one `faultingThread` indexes, else the one marked `triggered`.
    private static func crashedThread(of body: [String: Any]) -> [String: Any]? {
        let threads = body["threads"] as? [[String: Any]] ?? []
        if let index = (body["faultingThread"] as? NSNumber)?.intValue, threads.indices.contains(index) {
            return threads[index]
        }
        return threads.first { ($0["triggered"] as? NSNumber)?.boolValue == true }
    }

    /// The deepest recursion a thread's recursion record carries.
    private static func recursionDepth(of thread: [String: Any]) -> Int? {
        let records = thread["recursionInfoArray"] as? [[String: Any]] ?? []
        return records.compactMap { ($0["depth"] as? NSNumber)?.intValue }.max()
    }
}
