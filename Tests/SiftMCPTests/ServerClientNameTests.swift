//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Covers the client name a server records at `initialize`, and what `swift-sure status` makes of it.
@Suite(.temporaryDirectories)
struct ServerClientNameTests {
    private static var reading: Date {
        Date(timeIntervalSince1970: 1_788_000_000)
    }

    private static func at(_ offset: TimeInterval) -> String {
        ServerLifecycleLog.stamp(Date(timeIntervalSince1970: 1_788_000_000 + offset))
    }

    private static func start(_ pid: Int32, at offset: TimeInterval = -600) -> ServerLifecycleEntry {
        ServerLifecycleEntry(event: "start", pid: pid, stamp: at(offset))
    }

    private static func client(_ pid: Int32, _ name: String, at offset: TimeInterval = -599) -> ServerLifecycleEntry {
        ServerLifecycleEntry(event: "client", pid: pid, stamp: at(offset), name: name)
    }

    private static func report(_ entries: [ServerLifecycleEntry], sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        try #require(ServerLifecycleReport.text(
            entries: entries,
            bootedAt: reading.addingTimeInterval(-3600),
            isRunning: { _ in false }
        ), sourceLocation: sourceLocation)
    }

    @Test
    func aRecordedClientIsReadBackWithItsNameCutToSixtyFourCharacters() throws {
        let directory = try TemporaryDirectory.make("client-name")
        let fileURL = directory.appendingPathComponent("server.jsonl")
        let log = ServerLifecycleLog(fileURL: fileURL)

        log.recordStart(pid: 909, session: nil, root: "/tmp/gizmo", now: Self.reading)
        log.recordClient(pid: 909, name: "Cursor", now: Self.reading)
        log.recordClient(pid: 910, name: String(repeating: "W", count: 100), now: Self.reading)
        let read = ServerLifecycleReport.entries(in: fileURL)

        #expect(read.count == 3)
        #expect(read[1].event == "client")
        #expect(read[1].pid == 909)
        #expect(read[1].name == "Cursor")
        #expect(read[2].name?.count == 64)
    }

    @Test
    func aCursorServerWhoseProcessIsGoneIsAnOrdinaryEnding() throws {
        let text = try Self.report([Self.start(101), Self.client(101, "Cursor")])

        #expect(text == "mcp servers — none running")
        #expect(!text.contains("never recorded a stop"))
    }

    @Test
    func anotherClientsServerWhoseProcessIsGoneIsStillVanished() throws {
        let text = try Self.report([Self.start(101), Self.client(101, "claude-code")])

        #expect(text.contains("never recorded a stop"))
        #expect(text.contains("pid 101"))
    }

    @Test
    func aStartWithNoClientIsStillVanished() throws {
        let text = try Self.report([Self.start(101)])

        #expect(text.contains("never recorded a stop"))
    }

    /// A recycled pid is not its predecessor's client: the second start has none of its own.
    @Test
    func aReusedPidDoesNotInheritTheEarlierClient() throws {
        let text = try Self.report([
            Self.start(101, at: -900),
            Self.client(101, "Cursor", at: -899),
            Self.start(101, at: -300),
        ])

        #expect(text.contains("1 started and never recorded a stop"))
        #expect(text.contains("pid 101"))
    }

    @Test
    func anInitializeNamingItsClientReportsTheNameOnce() async throws {
        let root = try TemporaryDirectory.make("client-root")
        let toServer = Pipe()
        let fromServer = Pipe()
        let names = Names()
        let server = MCPServer(
            input: toServer.fileHandleForReading,
            output: fromServer.fileHandleForWriting,
            defaultRoot: root,
            log: { _ in },
            clientNamed: { names.add($0) }
        )
        let task = Task { await server.run() }
        var responses = FileHandleLines.lines(from: fromServer.fileHandleForReading).makeAsyncIterator()

        for id in 1 ... 2 {
            let params: [String: Any] = ["protocolVersion": "2025-06-18", "clientInfo": ["name": "Cursor", "version": "1.0.0"]]
            var data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": "initialize", "params": params])
            data.append(0x0A)
            toServer.fileHandleForWriting.write(data)
            _ = await responses.next()
        }
        toServer.fileHandleForWriting.closeFile()
        _ = await task.value

        #expect(names.all == ["Cursor"])
    }

    @Test
    func aLogHoldingClientLinesStillPairsAStopWithItsStart() {
        let entries = [
            Self.start(101),
            Self.client(101, "claude-code"),
            Self.start(102),
            Self.client(102, "Cursor"),
            ServerLifecycleEntry(event: "stop", pid: 101, stamp: Self.at(-60), reason: "inputClosed"),
        ]

        #expect(ServerLifecycleReport.unclosedStarts(in: entries).map(\.pid) == [102])
    }
}

extension ServerClientNameTests {
    /// A trim that keeps a running server's start line from the dropped prefix keeps its client line too, right after it, or the server's later ending reads as a kill again.
    @Test
    func aTrimKeepsTheClientLineOfAServerStillRunningWithItsStart() throws {
        let directory = try TemporaryDirectory.make("client-trim")
        let fileURL = directory.appendingPathComponent("server.jsonl")
        let log = ServerLifecycleLog(fileURL: fileURL)
        let launched = ServerLifecycleReport.startTime(of: getpid()) ?? Self.reading
        let longAgo = Date(timeIntervalSince1970: 1_000_000)
        log.recordStart(pid: getpid(), session: nil, root: "/tmp/live", now: launched)
        log.recordClient(pid: getpid(), name: "Cursor", now: launched)
        for offset in 1 ... ServerLifecycleLog.entryCap {
            log.recordStart(pid: Int32(100_000 + offset), session: nil, root: "/tmp/filler", now: longAgo)
        }

        let read = ServerLifecycleReport.entries(in: fileURL)

        #expect(read.count <= ServerLifecycleLog.entryCap)
        #expect(read.prefix(2).map(\.event) == ["start", "client"])
        #expect(read.prefix(2).map(\.pid) == [getpid(), getpid()])
        #expect(read[1].name == "Cursor")
    }
}

extension ServerClientNameTests {
    /// Collects the names a server reports, from the actor's task to the test's.
    final class Names: @unchecked Sendable {
        private let lock = NSLock()
        private var held: [String] = []

        func add(_ name: String) {
            lock.lock()
            defer { lock.unlock() }
            held.append(name)
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return held
        }
    }
}
