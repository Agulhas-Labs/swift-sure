//
// Copyright © Agulhas Labs
//

import Foundation

/// The last coverage `run --coverage` measured in a repository, kept on disk, keyed to the tree it measured.
public struct CoverageRecord: Codable, Sendable, Equatable {
    /// The content key of the tree the run measured.
    public let tree: String
    /// The command the run launched.
    public let command: [String]
    /// Each changed file the run measured, repository-relative, with its executable lines' counts; empty for a file compiled with no code to run.
    public let measured: [String: [Int: UInt64]]
    /// The changed files no test bundle the run built compiles.
    public let unmeasured: [String]
    /// When the run measured, or `nil` for a record written without it.
    public let measuredAt: Date?

    public init(tree: String, command: [String], measured: [String: [Int: UInt64]], unmeasured: [String], measuredAt: Date? = Date()) {
        self.tree = tree
        self.command = command
        self.measured = measured
        self.unmeasured = unmeasured
        self.measuredAt = measuredAt
    }
}

public extension CoverageRecord {
    /// `<repoRoot>/.swift-sure/coverage.json`, the one record a repository keeps, replaced by each run that measures.
    static func location(in repoRoot: URL) -> URL {
        SiftPaths.cache(in: repoRoot).appendingPathComponent("coverage.json")
    }

    /// Replaces the repository's record with this one.
    func write(in repoRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: SiftPaths.cache(in: repoRoot), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: Self.location(in: repoRoot), options: .atomic)
    }
}
