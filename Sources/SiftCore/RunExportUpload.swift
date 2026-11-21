//
// Copyright © Agulhas Labs
//

import Foundation

/// The upload result an `xcodebuild -exportArchive` log carries when the export options name an upload destination.
///
/// Only two shapes are read: `Uploaded <name>`, which names the app, and `Upload succeeded.`, optionally behind a `Progress 100%: ` prefix. The last line of each shape wins, and the line naming the app is preferred. Where the log named the exported product (`Exported <name> to: <path>`), only `Uploaded <that name>` is the app's; where it did not, an `Uploaded` line whose remainder ends in `symbols` or a `dsym` word is the symbols' upload and is not read. A failed upload has no wording here: the export's own verdict carries it.
struct RunExportUpload {
    private var uploaded: String?
    private var succeeded: String?
    private var exportedName: String?

    /// The line to print under the verdict, or `nil` where the log held neither shape.
    var line: String? {
        (uploaded ?? succeeded).map { "upload: \($0)" }
    }

    /// Reads one log line, but only under the contract an `xcodebuild -exportArchive` invocation owes.
    mutating func read(_ raw: String, under contract: RunVerdict.Contract) {
        guard contract == RunVerdict.Contract.exportingAnArchive else {
            return
        }
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("Exported "), let end = text.range(of: " to: ") {
            exportedName = String(text[text.index(text.startIndex, offsetBy: "Exported ".count) ..< end.lowerBound])
        } else if text.hasPrefix("Uploaded "), namesTheApp(String(text.dropFirst("Uploaded ".count))) {
            uploaded = text
        } else if text == "Upload succeeded." || text == "Progress 100%: Upload succeeded." {
            succeeded = "Upload succeeded."
        }
    }

    /// Whether the remainder of an `Uploaded …` line is the app's: the exported product's name where the log gave one, otherwise anything that is not a symbols upload.
    private func namesTheApp(_ remainder: String) -> Bool {
        guard !remainder.isEmpty else {
            return false
        }
        if let exportedName {
            return remainder == exportedName
        }
        return !["dsym", "dsyms", "symbols"].contains { remainder.lowercased().hasSuffix($0) }
    }
}
