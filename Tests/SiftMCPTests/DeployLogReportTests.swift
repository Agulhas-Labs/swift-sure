//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftMCP
import Testing

/// Covers `swift-sure report --deploys`: the installer's log read back, one line per install, newest last.
@Suite(.temporaryDirectories)
struct DeployLogReportTests {
    /// Two installs print in the order they were written, a field the installer could not name reads `unknown`, and a line that is not JSON is skipped rather than fatal.
    @Test
    func twoDeploysAndAMalformedLineRender() throws {
        let directory = try TemporaryDirectory.make("deploy-log")
        let log = directory.appendingPathComponent("deploys.jsonl")
        let lines = [
            #"{"ts":"2026-10-11T08:00:00Z","version":"0.1.4","commit":"7e1b3b25","tree":"clean","binarySize":12500000}"#,
            "this line is not json",
            #"{"ts":"2026-10-12T09:30:00Z","version":null,"commit":null,"tree":"dirty","binarySize":null}"#,
        ]
        try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)

        let page = DeployLog.render(fileURL: log, trees: { [] })

        #expect(page.components(separatedBy: "\n") == [
            "2026-10-11T08:00:00Z  7e1b3b25  0.1.4  clean  12.5 MB",
            "2026-10-12T09:30:00Z  unknown  unknown  dirty  unknown",
        ])
    }

    /// The build column names what the build is: a release's commit, a local build's tree with the commit that has it when one is found, a line from before the log told the two apart by its tree lookup, and `unknown` where there is neither.
    @Test
    func theBuildColumnNamesACommitOrATreeAndFindsTheCommitOfATree() throws {
        let directory = try TemporaryDirectory.make("deploy-log-build")
        let log = directory.appendingPathComponent("deploys.jsonl")
        let tail = #""version":"0.1.8","tree":"clean","binarySize":1000000}"#
        let lines = [
            #"{"ts":"2026-10-11T08:00:00Z","commit":null,"sourceTree":"aaaa11111","# + tail,
            #"{"ts":"2026-10-12T08:00:00Z","commit":null,"sourceTree":"zzzz99999","# + tail,
            #"{"ts":"2026-10-13T08:00:00Z","commit":"cccc3333","sourceTree":null,"# + tail,
            #"{"ts":"2026-10-14T08:00:00Z","commit":"bbbb22222","# + tail,
            #"{"ts":"2026-10-15T08:00:00Z","commit":"qqqq77777","# + tail,
            #"{"ts":"2026-10-16T08:00:00Z","commit":null,"sourceTree":null,"# + tail,
        ]
        try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)
        var asked = 0
        let known = [(commit: "1111aaa", tree: "aaaa11111ffff"), (commit: "2222bbb", tree: "bbbb22222eeee")]

        let page = DeployLog.render(fileURL: log) {
            asked += 1
            return known
        }

        #expect(page.components(separatedBy: "\n") == [
            "2026-10-11T08:00:00Z  tree aaaa11111 (commit 1111aaa)  0.1.8  clean  1.0 MB",
            "2026-10-12T08:00:00Z  tree zzzz99999  0.1.8  clean  1.0 MB",
            "2026-10-13T08:00:00Z  commit cccc3333  0.1.8  clean  1.0 MB",
            "2026-10-14T08:00:00Z  tree bbbb22222 (commit 2222bbb)  0.1.8  clean  1.0 MB",
            "2026-10-15T08:00:00Z  qqqq77777  0.1.8  clean  1.0 MB",
            "2026-10-16T08:00:00Z  unknown  0.1.8  clean  1.0 MB",
        ])
        #expect(asked == 1)
    }

    /// A release line asks nothing of the repository: only a tree has a commit to look for.
    @Test
    func aReleaseLineNeverLooksUpATree() throws {
        let directory = try TemporaryDirectory.make("deploy-log-release")
        let log = directory.appendingPathComponent("deploys.jsonl")
        try #"{"ts":"2026-10-13T08:00:00Z","version":"0.1.8","commit":"cccc3333","sourceTree":null,"tree":"clean","binarySize":1000000}"#
            .write(to: log, atomically: true, encoding: .utf8)

        let page = DeployLog.render(fileURL: log) {
            Issue.record("the repository was asked about a release line")
            return []
        }

        #expect(page == "2026-10-13T08:00:00Z  commit cccc3333  0.1.8  clean  1.0 MB")
    }

    /// A machine that has never installed from the bundle gets a sentence, not an empty answer.
    @Test
    func noLogSaysSo() throws {
        let directory = try TemporaryDirectory.make("deploy-log-none")

        let page = DeployLog.render(fileURL: directory.appendingPathComponent("deploys.jsonl"))

        #expect(page.hasPrefix("no deploys recorded"))
    }

    /// The log sits in the state directory `SWIFT_SURE_HOME` names, and `--deploys` is a flag of `report`.
    @Test
    func theLogIsInTheStateDirectory() throws {
        let url = DeployLog.standardFileURL(environment: ["SWIFT_SURE_HOME": "/scratch/state"])

        #expect(url.path == "/scratch/state/deploys.jsonl")
        #expect(try ReportCommand.parse(["--deploys"]).deploys)
    }

    /// A line that is not valid UTF-8 costs that line, not the file: the rows on either side of it are still listed.
    @Test
    func aLineOfInvalidUTF8DoesNotHideTheRowsAroundIt() throws {
        let directory = try TemporaryDirectory.make("deploy-log-bytes")
        let log = directory.appendingPathComponent("deploys.jsonl")
        var bytes = Data()
        for day in 10 ... 12 {
            bytes.append(Data(#"{"ts":"2026-10-\#(day)T08:00:00Z","version":"0.1.4","commit":"abc","tree":"clean","binarySize":1000000}"#.utf8))
            bytes.append(UInt8(ascii: "\n"))
        }
        bytes.append(contentsOf: [0xFF, 0xFE, UInt8(ascii: "\n")])
        for day in 13 ... 14 {
            bytes.append(Data(#"{"ts":"2026-10-\#(day)T08:00:00Z","version":"0.1.4","commit":"abc","tree":"clean","binarySize":1000000}"#.utf8))
            bytes.append(UInt8(ascii: "\n"))
        }
        try bytes.write(to: log)

        let rows = DeployLog.render(fileURL: log, trees: { [] }).components(separatedBy: "\n")

        #expect(rows.map { String($0.prefix(10)) } == (10 ... 14).map { "2026-10-\($0)" })
    }

    /// `--deploys` stands in for the page, so an option that shapes the page is refused rather than ignored.
    @Test
    func deploysRefusesEveryOtherReportOption() throws {
        #expect(throws: (any Error).self) { try ReportCommand.parse(["--deploys", "--since", "bogus"]) }
        #expect(throws: (any Error).self) { try ReportCommand.parse(["--deploys", "--out", "page.html"]) }
        #expect(throws: (any Error).self) { try ReportCommand.parse(["--deploys", "--no-open"]) }
        #expect(try ReportCommand.parse(["--deploys"]).deploys)
    }
}
