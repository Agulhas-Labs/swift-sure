//
// Copyright © Agulhas Labs
//

import CryptoKit
import Fieldwork
import Foundation
import SiftCore

/// The hook answers each context has already been given, so that one context draws a given answer about a file at most once: a parse block for one content, a stop gate for one tree.
///
/// One empty file per answer given, named by a digest of the three, created exclusively: the create is the check and the record at once, so two hooks racing over the same edit cannot both win it.
public struct HookMarks: Sendable {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Kept in the advice directory beside the ledger, so `SWIFT_SURE_ADVICE_DIR` redirects both together.
    public static func standard() -> HookMarks {
        HookMarks(directory: AdviceLedger.standardDirectory().appendingPathComponent("reuse", isDirectory: true))
    }

    /// Claims the answer about `declaration` in `file` for `context`, answering whether this call is the first to.
    ///
    /// A directory that cannot be prepared claims nothing: an answer left unsaid costs nothing, where one repeated on every edit would teach the model to skip them.
    public func claim(context: String, file: String, declaration: String) -> Bool {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data([context, CanonicalPath.of(file), declaration].joined(separator: "\n").utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let descriptor = open(directory.appendingPathComponent(name).path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
