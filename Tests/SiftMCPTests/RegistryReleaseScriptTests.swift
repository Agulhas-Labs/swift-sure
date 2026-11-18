//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// Covers the registry release script and the workflow that runs it, with a stand-in `gh` serving a folder of release assets and logging what is uploaded.
@Suite(.temporaryDirectories)
struct RegistryReleaseScriptTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static var assetName: String {
        "swift-sure-mcp-1.2.3.mcpb"
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

    @Test
    func aReleaseWithoutTheBundleGetsItUploaded() throws {
        let release = try Release()

        let result = try release.run()

        #expect(result.status == 0, "\(result.output)")
        #expect(result.uploads.contains("\(release.root.path)/work/out/\(Self.assetName)"), "\(result.uploads)")
        #expect(FileManager.default.fileExists(atPath: release.root.appendingPathComponent("work/out/server.json").path))
        #expect(result.output.hasSuffix("work/out/server.json\n"), "\(result.output)")
    }

    @Test
    func aReleaseHoldingTheIdenticalBundleIsLeftAlone() throws {
        let release = try Release()
        _ = try release.run()
        try FileManager.default.removeItem(at: release.log)
        try FileManager.default.copyItem(at: release.bundle(), to: release.assets.appendingPathComponent(Self.assetName))

        let result = try release.run(work: "again")

        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("already on v1.2.3, identical"), "\(result.output)")
        #expect(result.uploads.isEmpty, "\(result.uploads)")
    }

    @Test
    func aReleaseHoldingADifferentBundleKeepsItAndTheEntryCarriesItsChecksum() throws {
        let release = try Release()
        let held = release.assets.appendingPathComponent(Self.assetName)
        try "not the same bytes".write(to: held, atomically: true, encoding: .utf8)

        let result = try release.run()

        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("differs from the rebuilt one"), "\(result.output)")
        #expect(result.uploads.isEmpty, "\(result.uploads)")
        let entry = try String(contentsOf: release.root.appendingPathComponent("work/out/server.json"), encoding: .utf8)
        let checksum = try Self.tool("/usr/bin/shasum", ["-a", "256", held.path]).split(separator: " ").first.map(String.init) ?? ""
        #expect(!checksum.isEmpty && entry.contains("\"fileSha256\": \"\(checksum)\""), "\(entry)")
    }

    @Test
    func aReleaseWithTwoTarballsIsRefused() throws {
        let release = try Release()
        try FileManager.default.copyItem(
            at: release.assets.appendingPathComponent("swift-sure-1.2.3-abc1234-arm64.tar.gz"),
            to: release.assets.appendingPathComponent("swift-sure-1.2.3-def5678-arm64.tar.gz")
        )

        let result = try release.run()

        #expect(result.status == 1)
        #expect(result.output.contains("does not have exactly one"), "\(result.output)")
        #expect(result.uploads.isEmpty, "\(result.uploads)")
    }

    @Test
    func aTarballOfAnotherVersionIsRefused() throws {
        let release = try Release(builtVersion: "9.9.9")

        let result = try release.run()

        #expect(result.status == 1)
        #expect(result.output.contains("the tarball is version '9.9.9', the tag is 1.2.3"), "\(result.output)")
        #expect(result.uploads.isEmpty, "\(result.uploads)")
    }

    @Test
    func aDryRunUploadsNothing() throws {
        let release = try Release()

        let result = try release.run(dryRun: true)

        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("dry run: would upload \(Self.assetName)"), "\(result.output)")
        #expect(result.uploads.isEmpty, "\(result.uploads)")
    }

    @Test
    func aNameThatIsNotAReleaseTagIsRefused() throws {
        let release = try Release()

        let result = try release.run(tag: "main")

        #expect(result.status == 1)
        #expect(result.output.contains("is not a release tag"), "\(result.output)")
    }

    /// The workflow publishes with the run's own identity, pins the publisher by hash, runs only in the public repository.
    @Test
    func theWorkflowPublishesWithOIDCFromAPinnedPublisherInThePublicRepositoryOnly() throws {
        let workflow = try String(contentsOf: Self.repository.appendingPathComponent(".github/workflows/registry.yml"), encoding: .utf8)

        #expect(workflow.contains("id-token: write"))
        #expect(workflow.contains("login github-oidc"))
        #expect(workflow.contains("types: [published]"))
        #expect(workflow.contains("if: github.repository == 'Agulhas-Labs/swift-sure'"))
        #expect(workflow.contains("sha256sum --check"))
        #expect(!workflow.contains("releases/latest"))
        #expect(workflow.contains("sh Distribution/registry-release.sh \"$TAG\""))
    }
}

private extension RegistryReleaseScriptTests {
    /// A release at `v1.2.3` whose tarball holds a dummy binary and a `BUILD_INFO` naming the version it was built as, a stand-in `gh` first on the PATH, and the script copied beside what it reads.
    struct Release {
        var root: URL
        var assets: URL
        var log: URL
        var script: URL
        var stubs: URL

        init(builtVersion: String = "1.2.3") throws {
            root = try TemporaryDirectory.make("registry-release")
            assets = root.appendingPathComponent("assets")
            stubs = root.appendingPathComponent("stubs")
            log = root.appendingPathComponent("uploads.log")
            let distribution = root.appendingPathComponent("repo/Distribution")
            for directory in [assets, stubs, distribution] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            for name in ["registry-release.sh", "registry-files.sh"] {
                try FileManager.default.copyItem(
                    at: RegistryReleaseScriptTests.repository.appendingPathComponent("Distribution/\(name)"),
                    to: distribution.appendingPathComponent(name)
                )
            }
            script = distribution.appendingPathComponent("registry-release.sh")

            let payload = root.appendingPathComponent("payload/swift-sure-dist")
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
            let binary = payload.appendingPathComponent("swift-sure")
            try "#!/bin/sh\necho dummy\n".write(to: binary, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
            try "version=\(builtVersion)\n".write(to: payload.appendingPathComponent("BUILD_INFO"), atomically: true, encoding: .utf8)
            _ = try RegistryReleaseScriptTests.tool("/usr/bin/tar", [
                "-czf", assets.appendingPathComponent("swift-sure-1.2.3-abc1234-arm64.tar.gz").path,
                "-C", root.appendingPathComponent("payload").path, "swift-sure-dist",
            ])

            let stubScript = """
            #!/bin/sh
            # release download <tag> -R <slug> --pattern <glob> --dir <dir> [--clobber] | release view … | release upload <tag> <file> …
            case "$2" in
                download)
                    pattern=""; directory=""
                    while [ "$#" -gt 0 ]; do
                        case "$1" in --pattern) pattern="$2" ;; --dir) directory="$2" ;; esac
                        shift
                    done
                    for file in "\(assets.path)"/*; do
                        case "$(basename "$file")" in $pattern) cp "$file" "$directory/" ;; esac
                    done ;;
                view) ls "\(assets.path)" ;;
                upload) echo "upload $4" >> "\(log.path)" ;;
            esac
            """
            let stub = stubs.appendingPathComponent("gh")
            try stubScript.write(to: stub, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        }

        func run(tag: String = "v1.2.3", dryRun: Bool = false, work: String = "work") throws -> Outcome {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path] + (dryRun ? ["--dry-run"] : []) + [tag, root.appendingPathComponent(work).path]
            process.environment = ["PATH": "\(stubs.path):/usr/bin:/bin", "HOME": root.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let uploads = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            return Outcome(status: process.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "", uploads: uploads)
        }

        func bundle(work: String = "work") -> URL {
            root.appendingPathComponent("\(work)/out/\(RegistryReleaseScriptTests.assetName)")
        }
    }

    struct Outcome {
        var status: Int32
        var output: String
        var uploads: String
    }
}
