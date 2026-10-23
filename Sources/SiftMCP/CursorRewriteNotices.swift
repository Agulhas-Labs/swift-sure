//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation

/// The notice a Cursor `preToolUse` rewrite leaves for the same call's `postToolUse`, one small file per call.
///
/// Cursor carries no context from a `preToolUse` answer to the model but does carry it from a `postToolUse` one, and the two hooks are separate processes; the ticket is how the second learns what the first did. A ticket is named from a hash of the session and the call, so no raw identifier is written, and every error is swallowed: a hook never fails a call over a notice.
public struct CursorRewriteNotices: Sendable {
    /// How long a ticket lives before a filing or a read prunes it, for a call whose `postToolUse` never fired; longer than any build the hook is likely to wrap.
    public static let lifetime: TimeInterval = 60 * 60

    private let directory: URL
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// The tickets under the advice directory, which `SWIFT_SURE_ADVICE_DIR` redirects.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> CursorRewriteNotices {
        CursorRewriteNotices(directory: AdviceLedger.standardDirectory(environment: environment).appendingPathComponent("cursor-rewrites", isDirectory: true))
    }

    /// Writes `notice` for the call `call` of `session`, after deleting the tickets older than ``lifetime``.
    public func file(_ notice: String, session: String, call: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        prune()
        try? Data(notice.utf8).write(to: ticket(session: session, call: call), options: .atomic)
    }

    /// The notice filed for the call, deleted as it is read, or `nil` where there is none; the tickets older than ``lifetime`` are deleted first.
    public func take(session: String, call: String) -> String? {
        prune()
        let url = ticket(session: session, call: call)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return String(data: data, encoding: .utf8)
    }

    private func prune() {
        let manager = FileManager.default
        let cutoff = now().addingTimeInterval(-Self.lifetime)
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? manager.removeItem(at: file)
            }
        }
    }

    private func ticket(session: String, call: String) -> URL {
        let digest = SHA256.hash(data: Data("\(session)\u{0}\(call)".utf8))
        return directory.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }
}
