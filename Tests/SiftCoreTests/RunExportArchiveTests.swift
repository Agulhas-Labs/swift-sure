//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// An `xcodebuild -exportArchive` run owes `** EXPORT SUCCEEDED **`, and an upload's result is the one extra line its answer carries.
struct RunExportArchiveTests {
    private static let invocation = ["xcodebuild", "-exportArchive", "-archivePath", "Gizmo.xcarchive", "-exportOptionsPlist", "Options.plist", "-exportPath", "out"]
    private static var logPath: String {
        "/Users/dev/Gizmo/.swift-sure/runs/run-20000101-120000-00000000.log"
    }

    /// The upload's result sits directly under the verdict line, naming the app, and the raw-log pointer stays.
    @Test
    func anUploadingExportCarriesOneUploadLineUnderItsVerdict() throws {
        let report = try TestSources.runReport("xcodebuild-export-archive-upload", invokedAs: Self.invocation, exitCode: 0)
        let lines = Self.answer(report, exitCode: 0).split(separator: "\n").map(String.init)

        #expect(report.verdict?.state == .succeeded)
        #expect(lines[0].hasPrefix("✔ xcodebuild"))
        #expect(lines[1] == "upload: Uploaded Gizmo")
        #expect(lines.filter { $0.hasPrefix("upload:") }.count == 1)
        #expect(!lines[0].contains("could not tell"))
        #expect(lines.contains { $0.hasPrefix("raw: ") && $0.contains("run-20000101-120000-00000000.log") })
    }

    /// An export to a folder has no upload result to name, so no line.
    @Test
    func anExportWithNoUploadGetsNoUploadLine() throws {
        let report = try TestSources.runReport("xcodebuild-export-archive-folder", invokedAs: Self.invocation, exitCode: 0)
        let answer = Self.answer(report, exitCode: 0)

        #expect(answer.hasPrefix("✔ xcodebuild"))
        #expect(!answer.contains("upload:"))
        #expect(answer.contains("raw: "))
    }

    /// A failed export keeps its own verdict and invents no upload wording.
    @Test
    func aFailedExportReadsFailedWithNoUploadLine() throws {
        let report = try TestSources.runReport("xcodebuild-export-archive-failure", invokedAs: Self.invocation, exitCode: 70)
        let answer = Self.answer(report, exitCode: 70)

        #expect(report.verdict?.state == .failed)
        #expect(!answer.contains("upload:"))
        #expect(answer.contains("** EXPORT FAILED **"))
        #expect(answer.contains("raw: "))
    }

    /// The bare `Upload succeeded.` line is read when no line names the app, and a log of another command never earns the line.
    @Test
    func onlyAnExportReadsTheUploadLines() {
        var filter = RunOutputFilter(invokedAs: Self.invocation)
        filter.consume(line: "Progress 100%: Upload succeeded.")
        filter.consume(line: "** EXPORT SUCCEEDED **")
        #expect(filter.finish(exitCode: 0).uploadLine == "upload: Upload succeeded.")

        var build = RunOutputFilter(invokedAs: ["xcodebuild", "build"])
        build.consume(line: "Uploaded Gizmo")
        build.consume(line: "** BUILD SUCCEEDED **")
        #expect(build.finish(exitCode: 0).uploadLine == nil)
    }

    private static func answer(_ report: RunReport, exitCode: Int32) -> String {
        RunReportRenderer(kind: .xcodebuild, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"))
            .render(report, exitCode: exitCode, logURL: URL(fileURLWithPath: logPath))
    }
}
