//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// Covers the formula script's command links, on a copy of the script and its inputs in a folder this suite owns, with an earlier name (`oldone`) in the copy of `install.sh`.
@Suite(.temporaryDirectories)
struct HomebrewBuildScriptTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // SiftCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository root

    /// The arguments `build.sh` is run with (itself, the tarball, the output), over a copy of what it reads, alone in its folder because the privacy check it runs reads the folders beside it, with `oldone` as the one earlier name, `template` as the formula template, and a tarball holding an executable that prints a version.
    private static func stage(template: (String) -> String) throws -> [String] {
        let root = try TemporaryDirectory.make("homebrew-build")
        let copy = root.appending(path: "copy")
        let distribution = copy.appending(path: "Distribution")
        let homebrew = distribution.appending(path: "homebrew")
        try FileManager.default.createDirectory(at: homebrew, withIntermediateDirectories: true)
        let install = try String(contentsOf: repository.appending(path: "Distribution/install.sh"), encoding: .utf8)
        let adjusted = install.replacingOccurrences(of: "\nLEGACY_NAMES=\"sift\"\n", with: "\nLEGACY_NAMES=\"oldone\"\n")
        try adjusted.write(to: distribution.appending(path: "install.sh"), atomically: true, encoding: .utf8)
        let formula = try String(contentsOf: repository.appending(path: "Distribution/homebrew/swift-sure.rb"), encoding: .utf8)
        try template(formula).write(to: homebrew.appending(path: "swift-sure.rb"), atomically: true, encoding: .utf8)
        for file in ["Distribution/homebrew/build.sh", "Distribution/verify-private.sh", "Distribution/private-terms.txt"] {
            try FileManager.default.copyItem(at: repository.appending(path: file), to: copy.appending(path: file))
        }

        let payload = root.appending(path: "payload")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let binary = payload.appending(path: "swift-sure")
        try "#!/bin/sh\necho 9.9.9\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let tarball = root.appending(path: "swift-sure.tar.gz")
        _ = try run("/usr/bin/tar", ["-czf", tarball.path, "-C", payload.path, "swift-sure"])

        return [homebrew.appending(path: "build.sh").path, tarball.path, root.appending(path: "formula.rb").path]
    }

    /// Runs `executable` with no `GIT_*` variable and a PATH without `brew`, so the audit is skipped.
    private static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let printed = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(data: printed, encoding: .utf8) ?? "")
    }

    @Test
    func theCommandLinksAppearUnderTheBinaryInstall() throws {
        let staged = try Self.stage { $0 }

        let result = try Self.run("/bin/sh", staged)

        #expect(result.status == 0, "\(result.output)")
        let lines = try String(contentsOfFile: staged[2], encoding: .utf8).components(separatedBy: "\n")
        let install = try #require(lines.firstIndex(of: "    bin.install \"swift-sure\""))
        #expect(lines[install + 1] == "    bin.install_symlink \"swift-sure\" => \"oldone\"")
    }

    @Test
    func aTemplateWithoutTheBinaryInstallLineFailsTheBuild() throws {
        let staged = try Self.stage { $0.replacingOccurrences(of: "    bin.install \"swift-sure\"\n", with: "    bin.install \"sift-renamed\"\n") }

        let result = try Self.run("/bin/sh", staged)

        #expect(result.status != 0)
        #expect(result.output.contains("no bin.install \"swift-sure\" line in the formula template"))
    }
}
