//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
@testable import SiftMCP
import Testing

/// The stop gate asks git once per repository whether its edited files are ignored, and once per directory for the repository it is in, with no discovery bound by the caller.
///
/// Serialized: the spawn observer is process-wide, and each test keeps only the spawns made inside its own directories.
@Suite(.serialized, .temporaryDirectories)
struct StopGitSpawnTests {
    /// Six edited files in two repositories: one `check-ignore` each, not one per file.
    @Test
    func theIgnoreRulesAreAskedOncePerRepository() async throws {
        let fixture = try StopGateFixture()
        let other = try MCPTestRepo.make(declaring: "Gauge")
        let files = try ["A", "B", "C"].map { try fixture.file("Sources/\($0)/One.swift") }
            + ["A", "B", "C"].map { name -> String in
                let url = other.appendingPathComponent("Sources/\(name)/Two.swift")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "struct Probe {}\n".write(to: url, atomically: true, encoding: .utf8)
                return url.path
            }

        let spawns = SpawnTally(inside: [fixture.repo.path, other.path])
        GitSpawnObserver.install(spawns.note)
        defer { GitSpawnObserver.remove() }
        let transcript = try fixture.transcript(files.enumerated().flatMap { index, file in
            [StopGateFixture.edit("e\(index)", path: file), StopGateFixture.result("e\(index)")]
        })
        let printed = await fixture.hook(["transcript_path": transcript])
        let reason = try #require(try StopGateFixture.blockReason(of: printed))

        #expect(reason.contains("3 Swift files"))
        #expect(spawns.count { $0.contains("check-ignore") } == 2)
    }

    /// With no discovery bound, as the live hook runs, a directory edited twice is asked of git once: the transcript's reading and the repositories' share the discovery the stop makes for itself.
    @Test
    func aStopWithNoDiscoveryBoundAsksEachDirectoryOnce() async throws {
        let fixture = try StopGateFixture()
        let other = try MCPTestRepo.make(declaring: "Gauge")
        let first = try fixture.file("Sources/A/One.swift")
        let second = try fixture.file("Sources/A/Two.swift")
        let transcript = try fixture.transcript([
            StopGateFixture.edit("e1", path: first), StopGateFixture.result("e1"),
            StopGateFixture.edit("e2", path: second), StopGateFixture.result("e2"),
            StopGateFixture.bash("r1", command: "swift-sure run -- swift build", cwd: other.path),
            StopGateFixture.result("r1"),
        ])

        let spawns = SpawnTally(inside: [fixture.repo.path, other.path])
        GitSpawnObserver.install(spawns.note)
        defer { GitSpawnObserver.remove() }
        let printed = await fixture.hook(["transcript_path": transcript])
        let reason = try #require(try StopGateFixture.blockReason(of: printed))

        #expect(reason.contains("2 Swift files"))
        let directory = URL(fileURLWithPath: first).deletingLastPathComponent().path
        #expect(spawns.count(in: directory) { $0.contains("--show-toplevel") } == 1)
    }

    /// The installed handler is called at the same stack depth on the thousandth spawn as on the first. It lives in this serialized suite because the observer is process-wide: two tests installing it at once would replace each other's handler.
    @Test
    func theInstalledHandlerRunsAtTheSameDepthOnEverySpawn() throws {
        let probe = try TemporaryDirectory.make("depth")
        let depths = DepthTally()
        GitSpawnObserver.install { _, directory in
            guard directory == probe else { return }
            depths.note()
        }
        defer { GitSpawnObserver.remove() }

        for _ in 0 ..< 1000 {
            GitSpawnObserver.notify([], in: probe)
        }

        let recorded = depths.recorded
        #expect(recorded.count == 1000)
        #expect(Set(recorded).count == 1, "the call went \(recorded.first.map { $0 - (recorded.last ?? $0) } ?? 0) bytes deeper over 1000 spawns")
    }
}

private extension StopGitSpawnTests {
    /// The git spawns made inside some directories, from whichever thread made them.
    final class SpawnTally: @unchecked Sendable {
        private let lock = NSLock()
        private let roots: [String]
        private var spawns: [(arguments: [String], directory: String)] = []

        init(inside roots: [String]) {
            self.roots = roots.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        }

        var note: @Sendable ([String], URL) -> Void {
            { arguments, directory in
                let path = directory.resolvingSymlinksInPath().path
                guard self.roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return }
                self.lock.withLock { self.spawns.append((arguments, path)) }
            }
        }

        /// How many spawns made anywhere inside the directories the tally watches have arguments `matching` accepts.
        func count(where matching: ([String]) -> Bool) -> Int {
            lock.withLock { spawns.filter { matching($0.arguments) }.count }
        }

        /// The same, for spawns made in `directory` itself.
        func count(in directory: String, where matching: ([String]) -> Bool) -> Int {
            let target = URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
            return lock.withLock { spawns.filter { $0.directory == target && matching($0.arguments) }.count }
        }
    }

    /// The stack address of each call's frame, from whichever thread made it.
    final class DepthTally: @unchecked Sendable {
        private let lock = NSLock()
        private var addresses: [Int] = []

        var recorded: [Int] {
            lock.withLock { addresses }
        }

        func note() {
            var marker = 0
            let address = withUnsafeMutablePointer(to: &marker) { Int(bitPattern: $0) }
            lock.withLock { addresses.append(address) }
        }
    }
}
