//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftMCP
import Testing

/// The Stop gate reads back the directory it wrote into its own named command, so a path with an apostrophe or a backslash must survive `ShellWord.quoted` and the gate's reader.
struct StopGateQuotedDirectoryTests {
    private static let paths = ["/tmp/it's a repo", "/tmp/a b", "/tmp/back\\slash", "/tmp/it's \\ both"]

    @Test(arguments: paths)
    func aRootRunReadsBackItsDirectory(path: String) {
        let segment = "swift-sure run --root \(ShellWord.quoted(path)) -- swift build"

        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: segment, cwd: "/w/repo") == [path])
    }

    @Test(arguments: paths)
    func aRootEqualsRunReadsBackItsDirectory(path: String) {
        let segment = "swift-sure run --root=\(ShellWord.quoted(path)) -- swift build"

        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: segment, cwd: "/w/repo") == [path])
    }

    @Test(arguments: paths)
    func aSubshellCdReadsBackItsDirectory(path: String) {
        let command = "(cd \(ShellWord.quoted(path)) && swift-sure run -- swift build)"

        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: command, cwd: "/w/repo") == [path])
    }

    @Test
    func aComputedRootKeepsItsWrittenReading() {
        let segment = "swift-sure run --root \"$DIR/x\" -- swift build"

        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: segment, cwd: "/w/repo") == ["/w/repo/$DIR/x"])
    }
}
