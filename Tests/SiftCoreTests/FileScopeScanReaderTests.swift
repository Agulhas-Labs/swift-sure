//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the file-scope macro scan through an injected reader: how many reads it has in flight, that it stops starting reads once the verdict is known and tells the reads still running, and that its verdict holds under shuffled orders and read times.
struct FileScopeScanReaderTests {
    private static let root = URL(fileURLWithPath: "/scan-root")

    /// A file the scan parses that holds nothing at file scope a macro may declare a name with.
    private static func quiet(_ index: Int) -> String {
        "import Testing\n@Test func anchor\(index)() {}\n"
    }

    /// A file-scope declaration carrying another package's attribute, which may add any name beside it.
    private static var blocking: String {
        "@Aliased func anchor() {}\n"
    }

    /// A tree's declaration of a macro named `Test`, which makes every other file's `@Test` maybe another module's.
    private static var declaringTest: String {
        "@attached(peer) public macro Test(tag: Int) = #externalMacro(module: \"DepotKit\", type: \"Stamp\")\n"
    }

    /// The paths of `count` files.
    private static func paths(_ count: Int) -> [String] {
        (0 ..< count).map { "f\($0).swift" }
    }

    /// The sources by file, every file quiet but those of `sources`, keyed by index.
    private static func tree(_ count: Int, with sources: [Int: String] = [:]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (0 ..< count).map { ("f\($0).swift", sources[$0] ?? quiet($0)) })
    }

    /// The verdict of a scan of `order` through `recorder`, `width` reads at a time.
    private static func scan(_ order: [String], _ recorder: Recorder, width: Int) async -> Bool {
        await BareNameOutsideTypes.expandsAtFileScope(paths: order, under: root, width: width) { recorder.contents($0) }
    }

    /// A width of two keeps two reads in flight, no more and no fewer, over a dozen files.
    @Test
    func theWidthBoundsTheReadsInFlight() async {
        let recorder = Recorder(Self.tree(12), holdForPeer: true)

        let expands = await Self.scan(Self.paths(12), recorder, width: 2)

        #expect(!expands)
        #expect(recorder.snapshot.read.count == 12)
        #expect(recorder.snapshot.maxInFlight == 2)
    }

    /// With one read at a time and the blocking file first, the scan reads that file and starts no other.
    @Test
    func noReadStartsOnceTheVerdictIsKnown() async {
        let recorder = Recorder(Self.tree(12, with: [0: Self.blocking]))

        let expands = await Self.scan(Self.paths(12), recorder, width: 1)

        #expect(expands)
        #expect(recorder.snapshot.read == ["f0.swift"])
    }

    /// A read still running when another settles the verdict is cancelled, rather than left to run out.
    @Test
    func aReadStillRunningIsToldToStop() async {
        let recorder = Recorder(Self.tree(12, with: [0: Self.blocking]), holdUntilCancelled: ["f1.swift"])

        let expands = await Self.scan(Self.paths(12), recorder, width: 2)
        let seen = recorder.snapshot

        #expect(expands)
        #expect(Set(seen.read).isSubset(of: ["f0.swift", "f1.swift"]))
        #expect(seen.read.contains("f1.swift") == seen.cancelSeen.contains("f1.swift"))
    }

    /// Whatever the order of the files, the width and which read finishes first, the verdict is the one-at-a-time scan's.
    @Test
    func theVerdictHoldsUnderShuffledOrdersAndReadTimes() async {
        let scanned: [String: (sources: [String: String], expands: Bool)] = [
            "none": (Self.tree(12), false),
            "one blocking": (Self.tree(12, with: [7: Self.blocking]), true),
            "two blocking": (Self.tree(12, with: [2: Self.blocking, 9: Self.blocking]), true),
            "a macro Test declared": (Self.tree(12, with: [4: Self.declaringTest]), true),
        ]
        var generator = SplitMix64(state: 585)
        for shuffle in 0 ..< 12 {
            let order = Self.paths(12).shuffled(using: &generator)
            let delays = Dictionary(uniqueKeysWithValues: order.map { ($0, UInt32.random(in: 0 ... 1500, using: &generator)) })
            for (name, scene) in scanned.sorted(by: { $0.key < $1.key }) {
                let serial = await Self.scan(order, Recorder(scene.sources, delays: delays), width: 1)
                for width in [-1, 0, 1, 2, 5, 16, 200] {
                    let expands = await Self.scan(order, Recorder(scene.sources, delays: delays), width: width)

                    #expect(expands == serial, "\(name), shuffle \(shuffle), width \(width)")
                    #expect(expands == scene.expands, "\(name), shuffle \(shuffle), width \(width)")
                }
            }
        }
    }
}

extension FileScopeScanReaderTests {
    /// A seeded generator, so a shuffle is the same on every run.
    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    /// What the scan did to a recorder's reader.
    struct Snapshot {
        var maxInFlight = 0
        var read: [String] = []
        var cancelSeen: Set<String> = []
    }

    /// A reader that serves its sources and records what the scan does to it.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private let sources: [String: String]
        private let holdUntilCancelled: Set<String>
        private let holdForPeer: Bool
        private let delays: [String: UInt32]
        private var inFlight = 0
        private var firstReturnAt: Date?
        private var peerWaitAbandoned = false
        private var state = Snapshot()

        init(_ sources: [String: String], holdForPeer: Bool = false, holdUntilCancelled: Set<String> = [], delays: [String: UInt32] = [:]) {
            self.sources = sources
            self.holdForPeer = holdForPeer
            self.holdUntilCancelled = holdUntilCancelled
            self.delays = delays
        }

        var snapshot: Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return state
        }

        /// The source of the file at `path`, held first as the recorder was asked to, for a bounded time so a test cannot hang.
        func contents(_ path: String) -> Data? {
            let name = String(path.dropFirst(FileScopeScanReaderTests.root.path.count + 1))
            lock.lock()
            inFlight += 1
            state.maxInFlight = max(state.maxInFlight, inFlight)
            state.read.append(name)
            lock.unlock()
            if holdForPeer {
                // Held until a second read is in flight or none is left to start. Only broken code waits the bound out, so it costs a passing run nothing and is ten minutes (a pool starved under the full suite has taken minutes to start a task), and once one read has waited it out no other waits.
                let peerDeadline = Date().addingTimeInterval(600)
                while !peerInFlightOrNoneLeft() {
                    if Date() >= peerDeadline {
                        abandonPeerWait()
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            if holdUntilCancelled.contains(name) {
                // The cancel can only follow another read's return, so the wait without it counts from that return, not from this read's start. Only broken code waits it out, so it costs a passing run nothing and is ten minutes: under the full suite a starved pool has taken more than thirty seconds to resume the scan after the settling read returned. The half hour caps the wait on a scan that never settles.
                let outerDeadline = Date().addingTimeInterval(1800)
                while Date() < outerDeadline, !Task.isCancelled, !graceSincePeerReturnElapsed(600) {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                if Task.isCancelled {
                    lock.lock()
                    state.cancelSeen.insert(name)
                    lock.unlock()
                }
            }
            if let micros = delays[name] {
                Thread.sleep(forTimeInterval: Double(micros) / 1_000_000)
            }
            lock.lock()
            inFlight -= 1
            firstReturnAt = firstReturnAt ?? Date()
            lock.unlock()
            return sources[name].map { Data($0.utf8) }
        }

        /// Whether another read has returned and `seconds` have passed since.
        private func graceSincePeerReturnElapsed(_ seconds: TimeInterval) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return firstReturnAt.map { Date() >= $0.addingTimeInterval(seconds) } ?? false
        }

        /// Whether a second read is in flight, every file has been read, or a read has already waited the peer bound out.
        private func peerInFlightOrNoneLeft() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return inFlight >= 2 || state.read.count >= sources.count || peerWaitAbandoned
        }

        private func abandonPeerWait() {
            lock.lock()
            peerWaitAbandoned = true
            lock.unlock()
        }
    }
}
