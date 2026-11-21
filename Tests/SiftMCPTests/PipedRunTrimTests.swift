//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Covers a build or test whose pipe only cuts its output (`| head`, `| tail`, `| grep`): rewritten without the cut, a raw build wrapped as a bare one is, and every other pipeline left as it was read.
@Suite(.temporaryDirectories)
struct PipedRunTrimTests {
    /// A piped `swift-sure run`, in either spelling, keeps its first stage alone, without the `2>&1` that fed the pipe.
    @Test(arguments: [
        ("swift-sure run -- swift test 2>&1 | head -4", "swift-sure run -- swift test"),
        ("swift-sure run -- swift run generate-swift-format 2>&1 | tail -8", "swift-sure run -- swift run generate-swift-format"),
        ("swift-sure run --root /w -- swift test --filter Gizmo | grep -n error | tail -5", "swift-sure run --root /w -- swift test --filter Gizmo"),
        ("sift run -- swift build |& tail -3", "sift run -- swift build"),
    ])
    func aPipedRunKeepsItsFirstStage(shell: String, line: String) throws {
        let trim = try #require(PipedRunTrim.of(shell))

        #expect(trim.line == line)
        #expect(trim.legs == [line])
        #expect(trim.notice.contains("dropped `"))
    }

    /// A raw build piped only into trimmers is wrapped as the bare build is, the trimmers dropped.
    @Test(arguments: [
        ("swift test 2>&1 | tail -40", "swift-sure run -- swift test"),
        ("swift build | grep error", "swift-sure run -- swift build"),
        ("xcodebuild -scheme Gizmo test 2>&1 | grep -E 'error|FAIL' | head -20", "swift-sure run -- xcodebuild -scheme Gizmo test"),
    ])
    func aPipedRawBuildIsWrappedWithoutItsTrimmers(shell: String, line: String) throws {
        let trim = try #require(PipedRunTrim.of(shell))

        #expect(trim.line == line)
        #expect(trim.legs == [line])
        #expect(trim.notice.contains("Raw output: `\(line.dropFirst("swift-sure run -- ".count)) 2>&1 | cat`"))
    }

    /// Any stage that does more than cut, a redirection to a file, a follow, a count or a listing, and a line of several statements keep the reading they had.
    @Test(arguments: [
        "xcodebuild -scheme Gizmo test | xcbeautify",
        "swift test | tee log",
        "swift test > log",
        "swift test 2>&1 | tail -5 > log",
        "swift test | tail -f",
        "swift test | tail -F",
        "swift test | grep -c error",
        "swift test | grep -l error",
        "swift test | rg --count error",
        "swift test | wc -l",
        "swift build && swift test | tail -40",
        "(cd Kit && swift test) | tail -5",
        "swift test & tail -5",
        "swift-sure run -- swift test | tee log",
        "swift-sure run -- swift test && swift build | tail -5",
        "swiftlint lint --quiet | head -3",
    ])
    func everyOtherPipelineKeepsItsReading(shell: String) {
        #expect(PipedRunTrim.of(shell) == nil)
    }

    /// The trims leave the raw builds above exactly as they were read: no wrapping where none was offered.
    @Test
    func aKeptPipelineDrawsNoWrapping() {
        #expect(RunAdvice.suggestion(for: "xcodebuild -scheme Gizmo test | xcbeautify") == nil)
        #expect(RunAdvice.suggestion(for: "swift test | grep -c error") == nil)
        #expect(RunAdvice.suggestion(for: "swift build && swift test | tail -40") == nil)
        #expect(RunAdvice.suggestion(for: "swift-sure run -- swift test | tee log") == nil)
    }

    /// A line the trim applies to is never offered as advice: only the hook's amendment drops the pipe, so where it does not apply nothing can be refused.
    @Test(arguments: ["swift test 2>&1 | tail -40", "swift build 2>&1 | grep error", "swift-sure run -- swift test 2>&1 | head -4"])
    func aTrimmableLineDrawsNoAdvice(shell: String) {
        #expect(PipedRunTrim.of(shell) != nil)
        #expect(RunAdvice.suggestion(for: shell) == nil)
        #expect(RunAdvice.wrappedLegs(of: shell).isEmpty)
        #expect(RunAdvice.inPlaceRewrite(of: shell) == nil)
    }

    /// A statement run in the background would run in the foreground without its pipe, so it is never trimmed; one ended by `;` still is.
    @Test
    func aBackgroundedLineIsNotTrimmed() {
        #expect(PipedRunTrim.of("swift test 2>&1 | tail -5 &") == nil)
        #expect(PipedRunTrim.of("swift-sure run -- swift test | head -4 &") == nil)
        #expect(PipedRunTrim.of("swift test 2>&1 | tail -5;")?.line == "swift-sure run -- swift test")
    }

    /// A count, a listing or a silence is refused wherever its letter stands in a cluster, a value attached behind it included; a cluster whose only value-taking letter comes first is still a trimmer.
    @Test
    func aCountingClusterWithAnAttachedValueIsNotATrimmer() {
        for shell in ["swift test | grep -qm1 error", "swift test | grep -cm1 error", "swift test | rg -lm1 error", "swift test | grep -nq error"] {
            #expect(PipedRunTrim.of(shell) == nil, "\(shell)")
        }
        for shell in ["swift test | grep -m1 error", "swift test | grep -nm1 error"] {
            #expect(PipedRunTrim.of(shell)?.line == "swift-sure run -- swift test", "\(shell)")
        }
    }

    /// A count letter behind a digit cluster, and a directories action of `recurse` however it is written, make `grep` something other than a trimmer.
    @Test(arguments: [
        "swift build 2>&1 | grep -5c error",
        "swift build 2>&1 | grep -5nc error",
        "swift build 2>&1 | grep -d recurse error",
        "swift build 2>&1 | grep -drecurse error",
        "swift build 2>&1 | grep -nd recurse error",
        "swift build 2>&1 | grep --directories=recurse error",
        "swift build 2>&1 | grep --directories recurse error",
    ])
    func aCountOrRecursingGrepIsNotATrimmer(shell: String) {
        #expect(PipedRunTrim.of(shell) == nil, "\(shell)")
    }

    /// A context count, and a directories action that reads or skips, leave `grep` a trimmer.
    @Test(arguments: [
        "swift build 2>&1 | grep -5 error",
        "swift build 2>&1 | grep -5n error",
        "swift build 2>&1 | grep -d read error",
        "swift build 2>&1 | grep -dskip error",
        "swift build 2>&1 | grep --directories=skip error",
        "swift build 2>&1 | grep --directories read error",
    ])
    func aContextCountOrReadingGrepIsStillATrimmer(shell: String) {
        #expect(PipedRunTrim.of(shell)?.line == "swift-sure run -- swift build", "\(shell)")
    }

    /// A trimmer that reads a file, searches a tree or is handed an input redirection prints that instead of the run's output, so it is not dropped.
    @Test
    func aTrimmerReadingAFileIsNotATrimmer() {
        for shell in [
            "swift test | grep error Package.swift",
            "swift test | rg error Sources",
            "swift test | grep -r error .",
            "swift test | grep -R error",
            "swift test | grep --recursive error",
            "swift test | grep -e error Package.swift",
            "swift test | grep -f patterns.txt build.log",
            "swift test | tail -5 build.log",
            "swift test | head -n 4 build.log",
            "swift test | head -4 < /dev/null",
            "swift test | grep error < build.log",
            "swift test | grep",
        ] {
            #expect(PipedRunTrim.of(shell) == nil, "\(shell)")
        }
        for shell in ["swift test | grep -e error -e warning", "swift test | head -n 4", "swift test | tail -n +5", "swift test | rg -A 2 error", "swift test | grep -- -error"] {
            #expect(PipedRunTrim.of(shell)?.line == "swift-sure run -- swift test", "\(shell)")
        }
    }

    /// Where the rewrite would ask the user — default mode with no rule for the wrapping, or allow rules covering only the line as written — the built hook reads a piped line exactly as before the trim existed, let through with nothing denied or amended.
    ///
    /// An allow rule for the wrapping lets the trim go out as an amendment.
    @Test(arguments: [
        ("swift-sure run -- swift test 2>&1 | head -4", "allowed\t\tadviceTaken"),
        ("swift test 2>&1 | tail -40", "allowed\t\tnoLookup"),
    ])
    func whereTheRewriteWouldPromptThePipedLineIsReadAsBefore(shell: String, verdict: String) throws {
        let root = try Self.package()
        for allow in [[], ["Bash(swift test:*)", "Bash(tail:*)", "Bash(head:*)"]] {
            let home = try Self.home(allowing: allow)
            let printed = try Self.run(["pre-tool-use"], command: shell, in: root, home: home, mode: "default")
            let probed = try Self.run(["pre-tool-use", "--verdict"], command: shell, in: root, home: home, mode: "default")

            #expect(!printed.contains("deny") && !printed.contains("updatedInput"), "\(allow): \(printed)")
            #expect(probed.trimmingCharacters(in: .newlines) == verdict, "\(allow): \(probed)")
        }
        let allowed = try Self.home(allowing: ["Bash(swift-sure run:*)"])
        let probed = try Self.run(["pre-tool-use", "--verdict"], command: shell, in: root, home: allowed, mode: "default")

        #expect(probed.trimmingCharacters(in: .newlines).hasSuffix("\ttrimmed") && probed.hasPrefix("amended\t"), "\(probed)")
    }

    /// A package with one Swift target in a repository of its own.
    static func package() throws -> URL {
        let root = try ListedWideWindowTests.repository()
        try "// swift-tools-version:6.0\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])\n"
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return root
    }

    /// A home whose Claude configuration allows `rules` and nothing else.
    static func home(allowing rules: [String]) throws -> URL {
        let home = try TemporaryDirectory.make("piped-run-trim")
        let claude = home.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["permissions": ["allow": rules]]).write(to: claude.appendingPathComponent("settings.json"))
        return home
    }

    /// Through the built hook, plain and run-only, where nobody is asked: a piped `swift-sure run` and a piped `swift test` are handed back without their pipes, with the note saying why.
    @Test(arguments: [
        ("swift-sure run -- swift test 2>&1 | head -4", "swift-sure run -- swift test"),
        ("swift test 2>&1 | tail -40", "swift-sure run -- swift test"),
    ])
    func theBuiltHookDropsThePipe(shell: String, line: String) throws {
        let root = try Self.package()
        for arguments in [["pre-tool-use"], ["pre-tool-use", "--run-only"]] {
            let printed = try Self.run(arguments, command: shell, in: root, home: TemporaryDirectory.make("piped-run-trim"))
            let object = try JSONSerialization.jsonObject(with: Data(printed.utf8)) as? [String: Any]
            let specific = object?["hookSpecificOutput"] as? [String: Any]

            #expect((specific?["updatedInput"] as? [String: Any])?["command"] as? String == line, "\(arguments): \(printed)")
            #expect((specific?["additionalContext"] as? String)?.contains("dropped `") == true, "\(arguments): \(printed)")
        }
    }

    /// Runs the built hook with `arguments` on a Bash call of `command` in `root`, in permission mode `mode`, every state path and the Claude configuration under `home`: what it printed.
    static func run(_ arguments: [String], command: String, in root: URL, home: URL, mode: String = "auto", sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let binary = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle", sourceLocation: sourceLocation)
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["SWIFT_SURE_HOME"] = home.appendingPathComponent("swift-sure").path
        environment["SWIFT_SURE_SERVER_LOG"] = home.appendingPathComponent("server.jsonl").path
        environment["SWIFT_SURE_ADVICE_DIR"] = home.appendingPathComponent("advice").path
        environment["SWIFT_SURE_USAGE_LOG"] = home.appendingPathComponent("usage.jsonl").path
        environment["SWIFT_SURE_NO_ADVICE"] = nil
        environment["CLAUDE_CODE_SESSION_ID"] = nil
        environment["CLAUDE_CONFIG_DIR"] = home.appendingPathComponent("claude").path
        environment["CLAUDE_PROJECT_DIR"] = nil
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let payload: [String: Any] = [
            "session_id": "piped-run-trim", "cwd": root.path, "hook_event_name": "PreToolUse", "permission_mode": mode, "transcript_path": "",
            "tool_name": "Bash", "tool_input": ["command": command], "tool_use_id": "toolu-piped-run-trim",
        ]
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: payload))
        input.fileHandleForWriting.closeFile()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: printed, encoding: .utf8) ?? ""
    }
}
