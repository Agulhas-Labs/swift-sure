//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// An export's upload line is the app's verdict, never the line for its debug symbols.
struct RunExportUploadDSYMTests {
    private static let invocation = ["xcodebuild", "-exportArchive", "-archivePath", "Gizmo.xcarchive", "-exportOptionsPlist", "Options.plist", "-exportPath", "out"]

    /// A symbols upload printed after the app's still leaves the app's `Uploaded Gizmo` as the verdict.
    @Test
    func aSymbolsUploadLineAfterTheAppsLeavesTheAppsVerdict() throws {
        let text = try TestSources.runOutput("xcodebuild-export-archive-upload")
            .replacingOccurrences(of: "Uploaded Gizmo\n", with: "Uploaded Gizmo\nUploaded Gizmo dsyms\n")
        #expect(text.contains("Uploaded Gizmo dsyms"))
        var filter = RunOutputFilter(invokedAs: Self.invocation)
        filter.consume(Data(text.utf8))

        #expect(filter.finish(exitCode: 0).uploadLine == "upload: Uploaded Gizmo")
    }

    /// With the app's own line absent, a log whose only `Uploaded` line is the symbols' gives no upload verdict.
    @Test
    func aLogWhoseOnlyUploadedLineIsTheSymbolsGivesNoUploadVerdict() {
        var filter = RunOutputFilter(invokedAs: Self.invocation)
        filter.consume(line: "Uploaded Gizmo dsyms")
        filter.consume(line: "** EXPORT SUCCEEDED **")

        #expect(filter.finish(exitCode: 0).uploadLine == nil)
    }
}
