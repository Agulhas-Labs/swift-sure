//
// Copyright © Agulhas Labs
//

import Foundation

/// The upload result an `xcodebuild -exportArchive` log carries when the export options name an upload destination.
///
/// Only two shapes are read: `Uploaded <name>`, which names the app, and `Upload succeeded.`, optionally behind a `Progress 100%: ` prefix. The last line of each shape wins, and the line naming the app is preferred. A failed upload has no wording here: the export's own verdict carries it.
struct RunExportUpload {
    private var uploaded: String?
    private var succeeded: String?

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
        if text.hasPrefix("Uploaded "), text.count > "Uploaded ".count {
            uploaded = text
        } else if text == "Upload succeeded." || text == "Progress 100%: Upload succeeded." {
            succeeded = "Upload succeeded."
        }
    }
}
