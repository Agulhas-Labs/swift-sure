//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the one helper every subprocess in this module reads its output through.
///
/// It lives in a file of its own rather than beside either caller because both `GitContext.run` and `RunChangedFiles.inWorkingTree` depend on it, and a private helper on whichever type noticed the bug would leave the other caller deadlocking on identical code twenty lines away. A test filed under one of them would have said the same thing about where the rule lives.
@Suite(.temporaryDirectories)
struct ProcessStreamsTests {
    /// `GitContext` reads its subprocess through the same helper, so a repository whose file list overflows the pipe answers rather than hanging.
    ///
    /// Not a second deadlock test — `run` is private and `git` will not fill stderr to order, which is why the deadlock tests drive the helper directly (they live with it, in Fieldwork). This one pins the thing that can actually regress: that `GitContext` goes through `ProcessStreams` at all. Restore its own sequential read and a `git ls-files` over 1,000 files still returns, but the helper stops being the single implementation and the next caller inherits the bug again.
    @Test
    func gitContextReadsALongFileListThroughTheSharedDrain() throws {
        let root = try TestSources.makeTempRepo()
        // The paths have to carry the bytes, not the file contents: `git ls-files` prints names, so a
        // thousand one-line files still fits in one buffer. Long names get past 64 KB in 1,000 writes
        // rather than the ~2,300 the short ones would need, which keeps this test under a second.
        let padding = String(repeating: "Nested", count: 8)
        for index in 0 ..< 1000 {
            try TestSources.write("let value\(index) = \(index)\n", to: "Sources/\(padding)/File\(index).swift", in: root)
        }
        try TestSources.commitAll(in: root, message: "many files")

        let visible = try GitContext(repoRoot: root).visibleSwiftFiles()

        // Comfortably past the 64 KB a pipe holds, so the read genuinely spans more than one buffer.
        #expect(visible.count >= 1000)
        #expect(visible.joined(separator: "\n").utf8.count > 64 * 1024)
    }

    /// `GitContext.blobs(_:)` feeds `cat-file --batch` its requests on a pipe, written from a thread of its own, rather than through a temp file — so a batch whose input and output each overflow a pipe's 64 KB buffer must still answer every request, in order, rather than the write and the drain deadlocking each other.
    ///
    /// Pins the fix: a batch input written to `$TMPDIR` before `git` ran, and removed in a `defer`, leaked whenever the process was cut off before the `defer` ran — the session-start gather's 1.5s deadline being exactly that case. The pipe writes nothing to disk, so there is nothing left for a cut-off to leak.
    ///
    /// The path is long and the request count high rather than the blob itself, so the *input* line list clears 64 KB many times over — `content.txt` asked for 3005 times, the shape this test carried before, is only ~51 KB, comfortably under the buffer a synchronous write-then-drain would still pass. A path of ~200 characters asked for ~5,000 times puts the request list past 1 MB, genuinely spanning several buffers' worth on both the way in and the way out. `.timeLimit` fails the test on a hang rather than leaving the suite stuck with no report.
    @Test(.timeLimit(.minutes(1)))
    func blobsAnswersABatchThatOverflowsBothPipeBuffers() throws {
        let root = try TestSources.makeTempRepo()
        let segment = String(repeating: "Nested", count: 4)
        let directories = Array(repeating: segment, count: 8).joined(separator: "/")
        let path = "\(directories)/Content.txt"
        #expect(path.utf8.count > 190)
        try TestSources.write(String(repeating: "x", count: 100), to: path, in: root)
        try TestSources.commitAll(in: root, message: "add content")

        var requests = (0 ..< 5000).map { _ in (rev: "HEAD", path: path) }
        requests += (0 ..< 5).map { index in (rev: "HEAD", path: "missing-\(index).txt") }

        let results = try GitContext(repoRoot: root).blobs(requests)

        #expect(results.count == requests.count)
        for index in 0 ..< 5000 {
            #expect(results[index] == Data(String(repeating: "x", count: 100).utf8))
        }
        for index in 5000 ..< requests.count {
            #expect(results[index] == nil)
        }
    }
}

private extension ProcessStreamsTests {
    /// What the drain returned, handed back from the thread that waited on it.
    ///
    /// Unchecked because the semaphore is the ordering: the write happens before the signal and the read after the wait, and on the deadline path the value is only ever read as `nil`.
    final class Drained: @unchecked Sendable {
        var streams: (output: Data, failure: Data)?
    }
}
