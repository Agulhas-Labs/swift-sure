//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// A child the tests spawn holds none of the test process's other descriptors.
struct IsolatedSpawnTests {
    /// The case: a reader of a pipe, whose write end is still open in the test process when the child spawns, sees end-of-file once the test closes that end, while the child lives.
    @Test
    func aLiveChildDoesNotHoldAPipeWriteEndOpen() throws {
        let pipe = Pipe()
        let spawned = IsolatedSpawn.start("/bin/sleep", arguments: ["/bin/sleep", "600"])
        try #require(spawned.status == 0)
        defer {
            kill(spawned.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(spawned.pid, &status, 0)
        }
        try pipe.fileHandleForWriting.close()

        var descriptor = pollfd(fd: pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 1000)
        var byte: UInt8 = 0
        let count = read(pipe.fileHandleForReading.fileDescriptor, &byte, 1)

        #expect(ready == 1 && count == 0, "the pipe never reached end-of-file while the child lived: the child inherited its write end")
        #expect(kill(spawned.pid, 0) == 0, "the child was not alive to hold anything")
    }
}
