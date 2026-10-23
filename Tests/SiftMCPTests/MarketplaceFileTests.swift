//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// The plugin marketplace file the public cut carries.
///
/// The cut itself needs a real repository and the privacy gate, so the writer is a script of its own, run here, and the cut is checked to call it.
struct MarketplaceFileTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func output(of script: String, arguments: [String]) throws -> (status: Int32, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [repository.appendingPathComponent(script).path] + arguments
        process.environment = ["PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    /// The marketplace is not named for the product word, and lists the plugin by the path of its root.
    @Test
    func theMarketplaceIsNamedApartAndListsThePluginByPath() throws {
        let result = try Self.output(of: "Distribution/marketplace-file.sh", arguments: ["swift-sure"])
        #expect(result.status == 0, "\(result.text)")
        let file = try #require(JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any])
        #expect(file["name"] as? String == "swift-sure-plugins")
        #expect(file["name"] as? String != "swift-sure")
        #expect((file["owner"] as? [String: Any])?["name"] as? String == "Agulhas Labs")
        let plugins = try #require(file["plugins"] as? [[String: Any]])
        #expect(plugins.count == 1)
        #expect(plugins.first?["name"] as? String == "swift-sure")
        #expect(plugins.first?["source"] as? String == "./Distribution/plugin")
        let description = try #require(plugins.first?["description"] as? String)
        #expect(!description.isEmpty)
    }

    /// The name follows the product word it is given.
    @Test
    func theNameFollowsTheProductWord() throws {
        let result = try Self.output(of: "Distribution/marketplace-file.sh", arguments: ["gizmo"])
        let file = try #require(JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any])

        #expect(file["name"] as? String == "gizmo-plugins")
    }

    /// The cut writes the file at the target's root, through the writer, into the files it checks the commit against.
    @Test
    func theCutWritesTheFileThroughTheWriter() throws {
        let cut = try String(contentsOf: Self.repository.appendingPathComponent("Distribution/cut-public-repo.sh"), encoding: .utf8)
        let lines = cut.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("#") }

        #expect(lines.contains { $0.contains("MARKETPLACE_PATH=.claude-plugin/marketplace.json") })
        #expect(lines.contains { $0.contains("show \"$SHA:Distribution/marketplace-file.sh\" | sh -s -- swift-sure > \"$SCRATCH/marketplace.json\"") })
        #expect(!lines.contains { $0.contains("$REPO/Distribution/marketplace-file.sh") })
        #expect(lines.contains { $0.contains("cp \"$SCRATCH/marketplace.json\" \"$TARGET/$MARKETPLACE_PATH\"") })
        #expect(lines.contains { $0.contains(">> \"$SCRATCH/want\"") })
    }

    /// The cut refuses a commit that does not carry the plugin the marketplace points at.
    ///
    /// The cut cannot run in a test, so this is a text check.
    @Test
    func theCutRefusesACommitWithoutThePlugin() throws {
        let cut = try String(contentsOf: Self.repository.appendingPathComponent("Distribution/cut-public-repo.sh"), encoding: .utf8)
        let lines = cut.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("#") }

        #expect(lines.contains { $0 == "PLUGIN_PATH=Distribution/plugin/.claude-plugin/plugin.json" })
        #expect(lines.contains { $0.hasPrefix("grep -qxF \"$PLUGIN_PATH\" \"$SCRATCH/tree\"") })
        #expect(lines.contains { $0.contains("refuse \"$SHA does not carry $PLUGIN_PATH") })
    }
}
