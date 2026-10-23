//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Runs the bundle's real `install.sh` with a fake binary and a fake `claude` writing to one shared log, and checks the order of their calls.
@Suite(.temporaryDirectories)
struct InstallScriptServerOrderTests {
    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Distribution/install.sh")

    private static func executable(_ text: String, at url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The server is added before `install-hook` runs, because the hook tidy-up removes the earlier release's server only once the current one is registered.
    @Test
    func theServerIsRegisteredBeforeTheHooksTidyUp() throws {
        let directory = try TemporaryDirectory.make("install-server-order")
        let log = directory.appendingPathComponent("calls")
        let bundle = directory.appendingPathComponent("bundle", isDirectory: true)
        let bin = directory.appendingPathComponent("fake-bin", isDirectory: true)
        let home = directory.appendingPathComponent("home", isDirectory: true)
        for folder in [bundle, bin, home] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: Self.script, to: bundle.appendingPathComponent("install.sh"))
        try "rule\n".write(to: bundle.appendingPathComponent("SwiftSure.md"), atomically: true, encoding: .utf8)
        try Self.executable(
            "#!/bin/sh\n[ \"${1:-}\" = \"--version\" ] && echo 0.0.0-test\necho \"binary $*\" >> '\(log.path)'\nexit 0\n",
            at: bundle.appendingPathComponent("swift-sure")
        )
        try Self.executable("#!/bin/sh\necho \"claude $*\" >> '\(log.path)'\nexit 0\n", at: bin.appendingPathComponent("claude"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [bundle.appendingPathComponent("install.sh").path]
        process.environment = [
            "HOME": home.path,
            "SWIFT_SURE_HOME": directory.appendingPathComponent("state", isDirectory: true).path,
            "SWIFT_SURE_DEST": directory.appendingPathComponent("dest", isDirectory: true).path,
            "PATH": bin.path + ":/usr/bin:/bin",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        let add = lines.firstIndex { $0.hasPrefix("claude mcp add") }
        let hook = lines.firstIndex { $0.hasPrefix("binary install-hook") }
        #expect(process.terminationStatus == 0, "\(output)")
        #expect(add != nil && hook != nil, "\(lines)")
        if let add, let hook {
            #expect(add < hook, "\(lines)")
        }
    }
}
