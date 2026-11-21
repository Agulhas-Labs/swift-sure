//
// Copyright © Agulhas Labs
//

import Foundation

/// A pipeline that numbers one Swift file with `nl -ba` and hands the lines to nothing but windows — `nl -ba View.swift | sed -n 10,60p` — which is the window `cat -n View.swift | sed -n 10,60p` is in another spelling.
///
/// `nl` is no read verb of its own: `nl -ba View.swift` alone, or piped into anything but a window, stays what it always was, no lookup at all. Only the exact numbering `-ba` counts, because every other `nl` option renumbers, drops a line's number or reads section delimiters, and only one Swift file, because two are a sweep.
struct NumberedRead {
    /// Whether `stage` is `nl -ba` or a bare `nl` of one Swift file and nothing else: it prints every line of the file, and `-ba` numbers each as `cat -n` does, where a bare `nl` skips the blank ones, so its numbers are not the file's.
    static func numbersEveryLine(_ stage: ShellQuery) -> Bool {
        let words = stage.invocation
        guard words.first == "nl", let file = words.last, words.count == 2 || (words.count == 3 && words[1] == "-ba") else { return false }
        return stage.swiftFiles == [file] && stage.readPaths.count == 1
    }

    /// Where the stage that reads Swift stands among `stages`: the first that reads it itself, or else a leading ``numbersEveryLine(_:)`` stage that only windows follow.
    static func reader(of stages: [ShellQuery], holdsSource: ((String) -> Bool)?) -> Int? {
        if let reader = stages.firstIndex(where: { $0.readsSwift(holdsSource: holdsSource) }) {
            return reader
        }
        return intoWindows(stages) ? 0 : nil
    }

    /// Whether `stages` are a numbered read of one Swift file handed to nothing but windows.
    static func intoWindows(_ stages: [ShellQuery]) -> Bool {
        guard let first = stages.first, numbersEveryLine(first), stages.count > 1 else { return false }
        return stages.dropFirst().allSatisfy(\.windowsWhatItIsHanded)
    }
}
