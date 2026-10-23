//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Runs the real `registry-files.sh` on a dummy executable and reads back the bundle and the registry entry it writes.
@Suite(.temporaryDirectories)
struct RegistryFilesScriptTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static var version: String {
        "1.2.3"
    }

    /// The script is copied into a subdirectory of the temporary directory, as the other distribution-script tests do, and run with no `GIT_*` variable in its environment.
    private static func run(in directory: URL, executableName: String = "swift-sure", createBinary: Bool = true) throws -> Outcome {
        let scripts = directory.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let script = scripts.appendingPathComponent("registry-files.sh")
        try FileManager.default.copyItem(at: repository.appendingPathComponent("Distribution/registry-files.sh"), to: script)
        let source = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let binary = source.appendingPathComponent(executableName)
        if createBinary {
            try "#!/bin/sh\necho dummy\n".write(to: binary, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        let out = directory.appendingPathComponent("out", isDirectory: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, binary.path, version, out.path]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": directory.path]
        let pipe = Pipe()
        let errors = Pipe()
        process.standardOutput = pipe
        process.standardError = errors
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(
            status: process.terminationStatus,
            output: String(bytes: data, encoding: .utf8) ?? "",
            errors: String(bytes: errorData, encoding: .utf8) ?? "",
            directory: out,
            bundle: out.appendingPathComponent("\(executableName)-mcp-\(version).mcpb"),
            serverJSON: out.appendingPathComponent("server.json")
        )
    }

    private static func tool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private static func json(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
    }

    /// The bundle holds `manifest.json` and `bin/swift-sure` and nothing else.
    @Test
    func theBundleHoldsTheManifestAndTheBinary() throws {
        let outcome = try Self.run(in: TemporaryDirectory.make("registry-files-entries"))
        #expect(outcome.status == 0, "\(outcome.output)")
        let listing = try Self.tool("/usr/bin/zipinfo", ["-1", outcome.bundle.path])
        #expect(listing.split(separator: "\n").map(String.init).sorted() == ["bin/swift-sure", "manifest.json"])
    }

    /// The binary keeps its executable bit inside the zip, since an extracted binary without one cannot be started.
    @Test
    func theBinaryKeepsMode755InTheBundle() throws {
        let outcome = try Self.run(in: TemporaryDirectory.make("registry-files-mode"))
        #expect(outcome.status == 0, "\(outcome.output)")
        let listing = try Self.tool("/usr/bin/zipinfo", [outcome.bundle.path])
        let line = try #require(listing.split(separator: "\n").first { $0.hasSuffix("bin/swift-sure") })
        #expect(line.hasPrefix("-rwxr-xr-x"), "\(line)")
    }

    /// The manifest is version 0.3, a binary server started with `mcp`, for darwin, and its description says the bundle is arm64.
    @Test
    func theManifestDescribesTheBinaryServer() throws {
        let outcome = try Self.run(in: TemporaryDirectory.make("registry-files-manifest"))
        let manifest = try Self.json(Data(Self.tool("/usr/bin/unzip", ["-p", outcome.bundle.path, "manifest.json"]).utf8))
        #expect(manifest["manifest_version"] as? String == "0.3")
        #expect(manifest["name"] as? String == "swift-sure")
        #expect(manifest["version"] as? String == Self.version)
        let description = try #require(manifest["description"] as? String)
        #expect(description.contains("arm64"))
        #expect(description.contains("Intel"))
        let server = try #require(manifest["server"] as? [String: Any])
        #expect(server["type"] as? String == "binary")
        #expect(server["entry_point"] as? String == "bin/swift-sure")
        let config = try #require(server["mcp_config"] as? [String: Any])
        #expect(config["command"] as? String == "${__dirname}/bin/swift-sure")
        #expect(config["args"] as? [String] == ["mcp"])
        let compatibility = try #require(manifest["compatibility"] as? [String: Any])
        #expect(compatibility["platforms"] as? [String] == ["darwin"])
    }

    /// `server.json` names the product, carries the bundle's own SHA-256 and the release asset's URL, and keeps its description to 100 characters.
    @Test
    func theRegistryEntryCarriesTheBundlesChecksum() throws {
        let outcome = try Self.run(in: TemporaryDirectory.make("registry-files-server"))
        #expect(outcome.status == 0, "\(outcome.output)")
        let entry = try Self.json(Data(contentsOf: outcome.serverJSON))
        #expect(entry["$schema"] as? String == "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json")
        #expect(entry["name"] as? String == "io.github.Agulhas-Labs/swift-sure")
        #expect(entry["version"] as? String == Self.version)
        let description = try #require(entry["description"] as? String)
        #expect(!description.isEmpty && description.count <= 100, "\(description.count) characters")
        let packages = try #require(entry["packages"] as? [[String: Any]])
        #expect(packages.count == 1)
        let package = try #require(packages.first)
        #expect(package["registryType"] as? String == "mcpb")
        #expect(package["identifier"] as? String == "https://github.com/Agulhas-Labs/swift-sure/releases/download/v\(Self.version)/swift-sure-mcp-\(Self.version).mcpb")
        #expect((package["transport"] as? [String: Any])?["type"] as? String == "stdio")
        let expected = try Self.tool("/usr/bin/shasum", ["-a", "256", outcome.bundle.path]).split(separator: " ").first.map(String.init)
        #expect(package["fileSha256"] as? String == expected)
        #expect(expected?.count == 64)
        #expect(expected == expected?.lowercased())
    }

    /// A refusal is printed on stderr, so a caller that captures stdout still sees why it failed, and nothing reaches stdout.
    @Test
    func aMissingBinaryIsRefusedOnStandardError() throws {
        let outcome = try Self.run(in: TemporaryDirectory.make("registry-files-missing"), createBinary: false)

        #expect(outcome.status != 0)
        #expect(outcome.output.isEmpty, "\(outcome.output)")
        #expect(outcome.errors.contains("is not an executable file"), "\(outcome.errors)")
    }

    /// Every name derives from the executable's file name, so a renamed product renames the bundle, the entry and the URL together.
    @Test
    func namesFollowTheExecutablesName() throws {
        let outcome = try Self.run(in: TemporaryDirectory.make("registry-files-rename"), executableName: "gizmo")
        #expect(outcome.status == 0, "\(outcome.output)")
        let entry = try Self.json(Data(contentsOf: outcome.serverJSON))
        #expect(entry["name"] as? String == "io.github.Agulhas-Labs/gizmo")
        let package = try #require((entry["packages"] as? [[String: Any]])?.first)
        #expect((package["identifier"] as? String)?.hasSuffix("/v\(Self.version)/gizmo-mcp-\(Self.version).mcpb") == true)
    }
}

private extension RegistryFilesScriptTests {
    struct Outcome {
        var status: Int32
        var output: String
        var errors: String
        var directory: URL
        var bundle: URL
        var serverJSON: URL
    }
}
