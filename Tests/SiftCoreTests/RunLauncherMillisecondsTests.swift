//
// Copyright © Agulhas Labs
//

import Foundation
import os
@testable import SiftCore
import Testing

/// Covers what the launcher counts as the wrapped command's own time.
@Suite(.temporaryDirectories)
struct RunLauncherMillisecondsTests {
    /// The clock is read once as the command is launched and once as its output ends, and the first reading comes after the event stream's directory exists.
    ///
    /// The directory is made by the option probe and the sweep that precede it, so a first reading taken before them would count SwiftSure's own work as the command's. The clock here advances a second a reading, so the count is exact, and no wall-clock window is involved.
    @Test
    func theCountStartsOnceTheProbeAndTheSweepAreDone() throws {
        let root = try TestSources.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let swift = root.appendingPathComponent("swift")
        try """
        #!/bin/sh
        case " $* " in *" --help-hidden "*) echo "  --event-stream-output-path <path>"; exit 0 ;; esac
        echo "✔ Test run with 1 test in 1 suite passed after 0.001 seconds."
        exit 0

        """.write(to: swift, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swift.path)
        let streams = SiftPaths.cache(in: root).appendingPathComponent("run-events", isDirectory: true)
        let readings = OSAllocatedUnfairLock(initialState: [Bool]())
        let clock: @Sendable () -> Date = {
            let existed = FileManager.default.fileExists(atPath: streams.path)
            return readings.withLock { state in
                state.append(existed)
                return Date(timeIntervalSince1970: Double(state.count))
            }
        }
        let launcher = RunLauncher(workingDirectory: root, repositoryRoot: root, clock: clock)

        let outcome = try launcher.run([swift.path, "test"], readingEventStream: true)

        #expect(outcome.milliseconds == 1000)
        #expect(readings.withLock { $0 } == [true, true])
    }
}
