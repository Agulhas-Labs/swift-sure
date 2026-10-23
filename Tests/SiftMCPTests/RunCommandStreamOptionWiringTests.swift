//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// The event-stream option a wrapped `swift test` is given never reaches a signal line the answer quotes.
@Suite(.temporaryDirectories)
struct RunCommandStreamOptionWiringTests {
    /// The launcher tells the output filter which option it inserted, so a quoted signal line drops it.
    ///
    /// The stand-in prints the error line SwiftPM prints for a crashed test process, quoting its own argv, then exits non-zero. Set aside the launcher's hand-off of the inserted option to the filter and the line quotes the option and its deleted path.
    @Test
    func aQuotedSignalLineLeavesOutTheOptionTheLauncherInserted() throws {
        let directory = try TemporaryDirectory.make("run-command-stream-option-wiring")
        defer { try? FileManager.default.removeItem(at: directory) }
        let shim = directory.appendingPathComponent("swift")
        try """
        #!/bin/sh
        case " $* " in *" --help-hidden "*)
            echo "  --event-stream-output-path <event-stream-output-path>"
            exit 0 ;;
        esac
        echo "error: Process '$0 $*' exited with unexpected signal code 5"
        exit 1

        """.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let recorded = RecordedOutput()
        var command = try RunCommand.parse(["--", shim.path, "test", "--filter", "Gizmo"])
        command.log = RunUsageLog(fileURL: directory.appendingPathComponent("run.jsonl"))
        command.writesUnder = directory
        command.output = recorded.output
        command.inventoryBudget = 0

        try? command.run()

        let quoted = recorded.printed.components(separatedBy: "\n").filter { $0.contains("exited with unexpected signal code 5") }
        #expect(!quoted.isEmpty)
        for line in quoted {
            #expect(line.contains("\(shim.path) test --filter Gizmo'"))
            #expect(!line.contains("--event-stream-output-path"))
            #expect(!line.contains("run-events"))
        }
    }
}
