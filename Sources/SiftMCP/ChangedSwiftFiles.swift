//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore

/// The Swift files of a repository that changed during given spans of time.
public struct ChangedSwiftFiles {
    /// The absolute paths of the Swift files under `root`, tracked or untracked and not ignored, whose change time lies in any of `spans` widened by a millisecond each side, sorted.
    public static func under(_ root: String, changedWithin spans: [ClosedRange<Double>]) -> [String] {
        withSpanEnds(under: root, changedWithin: spans).map(\.path)
    }

    /// Each file ``under(_:changedWithin:)`` lists, sorted by path, with the upper bound of the latest span its change time lies in.
    public static func withSpanEnds(under root: String, changedWithin spans: [ClosedRange<Double>]) -> [(path: String, spanEnd: Double)] {
        let relative = (try? GitContext(repoRoot: URL(fileURLWithPath: root)).visibleSwiftFiles()) ?? []
        return relative.map { (root as NSString).appendingPathComponent($0) }.sorted().compactMap { path in
            guard let changed = FileChangeStat.of(path: path)?.changed else { return nil }
            let ends = spans.filter { ($0.lowerBound - 0.001) ... ($0.upperBound + 0.001) ~= changed }.map(\.upperBound)
            return ends.max().map { (path, $0) }
        }
    }
}
