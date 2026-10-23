//
// Copyright © Agulhas Labs
//

import Foundation

/// The lock notice SwiftPM writes to standard error, split from the output glued behind it.
struct RunLockNotice {
    /// SwiftPM's notice that another process holds the `.build` lock and the line it was glued to, or `nil` where `line` does not open on one with more after it.
    ///
    /// SwiftPM writes the notice to standard error with no newline — `… waiting until that process has finished execution...` while it waits, ``… but this will be ignored since `--ignore-lock` has been passed`` when it will not — so in a log of both streams it heads the next line the run prints, which under `swift test` is a test process's opening: `Test Suite 'All tests' started at` or `Test run started.`. Every reader anchors on a line's start, so an opening glued there went uncounted.
    static func split(_ line: String) -> (notice: String, rest: String)? {
        guard line.hasPrefix("Another instance of SwiftPM") else {
            return nil
        }
        let endings = ["waiting until that process has finished execution...", "but this will be ignored since `--ignore-lock` has been passed"]
        guard let end = endings.lazy.compactMap({ line.range(of: $0)?.upperBound }).first, end < line.endIndex else {
            return nil
        }
        return (notice: String(line[..<end]), rest: String(line[end...]))
    }
}
