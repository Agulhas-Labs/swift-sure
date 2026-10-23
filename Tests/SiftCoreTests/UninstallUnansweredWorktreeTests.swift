//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// A git that does not answer the linked-worktree question is not read as the answer that lets a removal run.
@Suite(.temporaryDirectories)
struct UninstallUnansweredWorktreeTests {
    /// The question is silent, and a later one would answer: `claude mcp remove` is not run, and the entry is named for removal by hand.
    @Test
    func aWorktreeQuestionGitDoesNotAnswerRefusesTheLocalRemoval() throws {
        let project = try CanonicalPath.of(TemporaryDirectory.make("uninstall-unanswered-worktree").path)
        let scratch = try TemporaryDirectory.make("uninstall-unanswered-worktree-config")
        let config = scratch.appendingPathComponent(".claude.json")
        let registration: [String: Any] = ["command": "npx", "args": ["--yes", "@agulhas-labs/sift", "mcp"]]
        try JSONSerialization.data(withJSONObject: ["mcpServers": [:], "projects": [project: ["mcpServers": ["swift-sure": registration]]]]).write(to: config)
        let locations = SiftUninstall.Locations(settings: scratch.appendingPathComponent("settings.json"), claudeConfig: config, rule: scratch.appendingPathComponent("swift-sure.md"), siftHome: scratch.appendingPathComponent(".swift-sure"), logs: [])
        var asked: [SiftUninstall.ServerScope] = []

        let silent: (URL) throws -> (own: URL, common: URL)? = { _ in throw EngineError.gitDidNotAnswer(project, seconds: 2) }

        let step = UninstallServers.settle(locations, roots: [], gitDirectories: silent) { scope in
            asked.append(scope)
            return .removed
        }

        #expect(asked.isEmpty, "claude mcp remove ran in a project whose worktree question went unanswered")
        #expect(step.failures == 1, "\(step.notes)")
        let prefix = "mcp: not removed — the local-scope server in \(project) runs npx --yes @agulhas-labs/sift mcp; git did not answer within "
        #expect(step.notes.contains { $0.hasPrefix(prefix) && $0.contains("by hand") }, "\(step.notes)")
    }

    /// The question fails for a reason that is not silence, such as git failing to launch: the refusal says it could not ask, and does not promise that git will answer later.
    @Test
    func aWorktreeQuestionThatFailsOtherwiseRefusesWithWordingThatFitsIt() throws {
        let project = try CanonicalPath.of(TemporaryDirectory.make("uninstall-failed-worktree").path)
        let scratch = try TemporaryDirectory.make("uninstall-failed-worktree-config")
        let config = scratch.appendingPathComponent(".claude.json")
        let registration: [String: Any] = ["command": "npx", "args": ["--yes", "@agulhas-labs/sift", "mcp"]]
        try JSONSerialization.data(withJSONObject: ["mcpServers": [:], "projects": [project: ["mcpServers": ["swift-sure": registration]]]]).write(to: config)
        let locations = SiftUninstall.Locations(settings: scratch.appendingPathComponent("settings.json"), claudeConfig: config, rule: scratch.appendingPathComponent("swift-sure.md"), siftHome: scratch.appendingPathComponent(".swift-sure"), logs: [])
        var asked: [SiftUninstall.ServerScope] = []

        let broken: (URL) throws -> (own: URL, common: URL)? = { _ in throw GitError(message: "cannot launch the tool") }

        let step = UninstallServers.settle(locations, roots: [], gitDirectories: broken) { scope in
            asked.append(scope)
            return .removed
        }

        #expect(asked.isEmpty, "claude mcp remove ran in a project whose worktree question failed")
        #expect(step.failures == 1, "\(step.notes)")
        let expected = "could not ask git whether \(project) is a linked worktree (cannot launch the tool); the local-scope entry is left alone"
        #expect(step.notes.contains { $0.contains(expected) && !$0.contains("Until it does") }, "\(step.notes)")
    }
}
