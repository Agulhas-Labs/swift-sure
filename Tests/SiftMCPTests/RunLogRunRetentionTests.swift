//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// The `raw:` line says a log is kept for the next four runs, so the count that prunes logs counts runs: a sharded `swift-sure test` opens a log for its build, its enumeration and every shard, and those are one run.
@Suite(.temporaryDirectories)
struct RunLogRunRetentionTests {
    private static func runsDirectory(in root: URL) -> URL {
        SiftPaths.cache(in: root).appendingPathComponent(RunLog.runsDirectoryName, isDirectory: true)
    }

    /// Opens a log, writes nothing and publishes it as finished at `finished`, which is what orders runs for the count.
    @discardableResult
    private static func finish(in root: URL, run: String?, at finished: Date, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let log = try #require(RunLog.open(inDirectory: root, run: run), sourceLocation: sourceLocation)
        log.close()
        try FileManager.default.setAttributes([.modificationDate: finished], ofItemAtPath: log.url.path)
        return log.url.lastPathComponent
    }

    private static func logs(in root: URL) throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: runsDirectory(in: root).path)
        return Set(names.filter { $0.hasPrefix("run-") && $0.hasSuffix(".log") })
    }

    @Test
    func aLogSurvivesOneShardedRun() throws {
        let root = try TemporaryDirectory.make("run-log-run-retention-sharded")
        let base = Date().addingTimeInterval(-1000)
        let earlier = try Self.finish(in: root, run: nil, at: base)

        let token = RunLog.newRunToken()
        for index in 0 ..< 6 {
            try Self.finish(in: root, run: token, at: base.addingTimeInterval(Double(index + 1)))
        }

        let logs = try Self.logs(in: root)

        #expect(logs.contains(earlier), "\(logs.sorted())")
        #expect(logs.count == 7, "\(logs.sorted())")
    }

    @Test
    func theBoundHoldsPerRun() throws {
        let root = try TemporaryDirectory.make("run-log-run-retention-bound")
        let base = Date().addingTimeInterval(-1000)
        var groups: [[String]] = []
        for group in 0 ..< RunLog.keptLogs {
            let token = RunLog.newRunToken()
            let older = try Self.finish(in: root, run: token, at: base.addingTimeInterval(Double(group * 10)))
            let newer = try Self.finish(in: root, run: token, at: base.addingTimeInterval(Double(group * 10 + 1)))
            groups.append([older, newer])
        }
        let before = try Self.logs(in: root)
        #expect(before.count == RunLog.keptLogs * 2, "\(before.sorted())")

        let sixth = try #require(RunLog.open(inDirectory: root, run: RunLog.newRunToken()))
        defer { sixth.close() }

        let after = try Self.logs(in: root)
        #expect(after == before.subtracting(groups[0]), "\(after.sorted())")
    }

    @Test
    func runsAreOrderedByTheirNewestLogNotTheirOldest() throws {
        let root = try TemporaryDirectory.make("run-log-run-retention-order")
        let base = Date().addingTimeInterval(-1000)
        let token = RunLog.newRunToken()
        let build = try Self.finish(in: root, run: token, at: base)
        var quick: [String] = []
        for index in 1 ... RunLog.keptLogs - 1 {
            try quick.append(Self.finish(in: root, run: nil, at: base.addingTimeInterval(Double(index))))
        }
        let shards = try [9.0, 10.0].map { try Self.finish(in: root, run: token, at: base.addingTimeInterval($0)) }

        let sixth = try #require(RunLog.open(inDirectory: root, run: RunLog.newRunToken()))
        defer { sixth.close() }

        let after = try Self.logs(in: root)

        #expect(after == Set([build] + shards + quick.dropFirst()), "\(after.sorted())")
    }

    @Test
    func aRunNeverPrunesItself() throws {
        let root = try TemporaryDirectory.make("run-log-run-retention-own")
        let base = Date().addingTimeInterval(-1000)
        let token = RunLog.newRunToken()
        let first = try Self.finish(in: root, run: token, at: base)
        var others: [String] = []
        for index in 0 ..< RunLog.keptLogs - 1 {
            try others.append(Self.finish(in: root, run: nil, at: base.addingTimeInterval(Double(index + 1))))
        }

        let second = try Self.finish(in: root, run: token, at: base.addingTimeInterval(100))

        let logs = try Self.logs(in: root)

        #expect(logs == Set(others + [first, second]), "\(logs.sorted())")
    }
}
