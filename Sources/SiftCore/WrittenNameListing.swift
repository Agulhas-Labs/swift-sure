//
// Copyright © Agulhas Labs
//

/// Whether an answer goes on to list any site or file by written name, kept by the blocks that list them.
///
/// A refusal printed above those blocks is worded by it, since the blocks run after the line is placed.
final class WrittenNameListing {
    private(set) var listsAny = false
    private var wordings: [String: String] = [:]

    func record(_ count: Int) {
        listsAny = listsAny || count > 0
    }

    /// Holds each refusal line as printed with the words it takes where an answer by written name follows, and counts the files the answer lists by name.
    func hold(_ refusalWordings: [String: String], listedFiles: Int) {
        wordings = refusalWordings
        record(listedFiles)
    }

    /// `lines` with each held refusal line in the words for the answer: unchanged where nothing was listed by written name.
    func wordingRefusals(in lines: [String]) -> [String] {
        listsAny ? lines.map { wordings[$0] ?? $0 } : lines
    }
}
