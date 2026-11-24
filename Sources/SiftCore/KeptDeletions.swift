//
// Copyright © Agulhas Labs
//

import Foundation

/// Which of the deleted files a query cites a build without cleaning keeps (Docs/Design.md §2), one per query and shared by every judge of it.
///
/// A cited deleted file is kept when all three hold: it lies inside the root, it was dropped at or before the anchor (the ledger dates it no later, or its nearest surviving directory was last modified before), and a unit on disk still names it (``StoreUnitMentions``). The ledger is read once, and only once a cited file is missing; each store's units directory is listed once, and each directory's date is asked once.
final class KeptDeletions {
    private var ledger: DeletionLedger?
    private var mentions: [String: StoreUnitMentions] = [:]
    private var directoryDates: [String: Double?] = [:]
    /// How many times the ledger was read, which is what makes the once-per-query claim checkable.
    private(set) var ledgerReads = 0

    /// Whether the missing file at the repo-relative `relative` is one a build without cleaning keeps, measured against `anchor` (already nudged past equality) and named by a unit of one of `stores`.
    func isKept(_ relative: String, anchor: Double, stores: [SemanticStore], root: URL, index: IndexStore) -> Bool {
        guard !relative.hasPrefix("/") else { return false }
        let datedBefore = ledger(of: index).entries[relative].map { !($0 > anchor) } ?? false
        guard datedBefore || Self.certainlyDeletedBefore(anchor, path: relative, root: root, modified: directoryDate) else { return false }
        return stores.contains { mentions(of: $0, root: root).names(file: relative) }
    }

    /// Whether the missing repo-relative `path` was certainly deleted before `moment`, judged by the modification time of its nearest surviving directory, as `modified` reads it.
    ///
    /// That time bounds the deletion from above, since removing an entry changes its directory's time and nothing sets that time back. False when no directory up to `root` can be read, keeping the ledger's moment.
    static func certainlyDeletedBefore(_ moment: Double, path: String, root: URL, modified: (String) -> Double? = modificationDate(of:)) -> Bool {
        var directory = root.appendingPathComponent(path).deletingLastPathComponent().standardizedFileURL
        let top = root.standardizedFileURL.path
        while true {
            if let date = modified(directory.path) {
                return date < moment
            }
            guard directory.path != top, directory.path.hasPrefix(top) else { return false }
            directory = directory.deletingLastPathComponent()
        }
    }

    /// The modification moment of the item at `path`, `nil` where it cannot be read.
    static func modificationDate(of path: String) -> Double? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970
    }

    private func ledger(of index: IndexStore) -> DeletionLedger {
        if let ledger {
            return ledger
        }
        ledgerReads += 1
        let read = (try? index.deletionLedger()) ?? DeletionLedger(metaValue: nil)
        ledger = read
        return read
    }

    private func mentions(of store: SemanticStore, root: URL) -> StoreUnitMentions {
        let path = store.cache.storePath
        if let known = mentions[path] {
            return known
        }
        let made = StoreUnitMentions(store: URL(fileURLWithPath: path), root: root)
        mentions[path] = made
        return made
    }

    private func directoryDate(_ path: String) -> Double? {
        if let known = directoryDates[path] {
            return known
        }
        let found = Self.modificationDate(of: path)
        directoryDates[path] = .some(found)
        return found
    }
}
