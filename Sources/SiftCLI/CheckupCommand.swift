//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SiftCore
import SiftMCP

/// `checkup`: what a change left unproved and what still leans on it, in one answer.
///
/// CLI only, on `diff`'s reasoning — it is run from a shell before a hand-back, and every MCP tool description is paid for in every session's context whether or not that session ever calls it.
struct CheckupCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "checkup",
            abstract: "What a change left unproved and what still leans on it, in one answer: every diagnostic that answers for the change, listed in one fixed order, each finding ending in the command that shows its detail.",
            discussion: """
            \(ProductName.current.binary) checkup builds nothing and runs nothing: whether the change was tested is what `\(ProductName.current.binary) run` recorded, never found out by running it. The change is the one `\(ProductName.current.binary) diff` reads, with no whole-tree mode. Exit 0 whenever it answered, findings or none; a range it refuses exits 1.
            """
        )
    }

    @Argument(help: "A single commit (its own change, against its first parent), A..B (the two revisions as named), or A...B (B against its merge-base with A). Omitted: the working tree against HEAD, untracked files included.")
    var range: String?

    @Option(help: "Skip this many finding lines (pagination cursor from a truncated: marker).")
    var offset = 0

    @OptionGroup var rootOptions: RootOptions

    /// Where the roots this run touches are recorded — the standard registry everywhere but a test.
    var registry: () -> RootsRegistry = { .standard() }

    func run() async throws {
        let (text, refused) = try await answer(registry: registry())
        StandardStreams.emit(text)
        if refused {
            throw ExitCode(1)
        }
    }

    /// The whole answer, header first and any adopted-root note under it, and whether it is a refusal of the range; `runLog` is the wrapped-run log the flaky check reads.
    func answer(registry: RootsRegistry = .standard(), runLog: URL = RunUsageLog.standardFileURL) async throws -> (text: String, refused: Bool) {
        let (engine, note) = try rootOptions.makeEngine(registry: registry)
        let git = GitContext(repoRoot: engine.repoRoot)
        let resolvedRange: DiffRange
        do {
            resolvedRange = try DiffRange.resolve(range, git: git, command: "checkup")
        } catch let refusal as DiffRange.Refusal {
            return (Freshness.placing([note], under: Freshness.liveHeaderLine(tree: engine.tree) + "\n" + refusal.message), true)
        }
        let freshness = try await engine.ensureFresh()
        let walk = CheckupAffectedWalk(engine: engine, range: resolvedRange)
        let spelledRange = range?.trimmingCharacters(in: .whitespaces)
        let outcomes = try await engine.checkup(range: resolvedRange, flakes: CheckupFlakes.evidence(logAt: runLog, root: engine.repoRoot.path), walk: walk, spelledRange: spelledRange)
        let text = try await CheckupFrame(git: git, range: resolvedRange, engine: engine, walk: walk, spelledRange: spelledRange).answer(freshness: freshness, notes: [note], offset: offset, outcomes: outcomes)
        return (text, false)
    }
}

extension CheckupCommand {
    /// Only what comes off the command line — `registry` is a seam, not an argument.
    enum CodingKeys: String, CodingKey {
        case range, offset, rootOptions
    }
}
