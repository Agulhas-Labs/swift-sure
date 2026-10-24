//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// Covers `pre-tool-use --run-only`, the hook `install --run-only` registers: silent on every lookup, with no advice state written for one, and the build and test rewrite unchanged.
///
/// Every call is made in a fixture repository under the temporary directory, never in this checkout: a checkout under `.build/` is a tree the plain hook never answers in, and the controls here need one it does.
@Suite(.temporaryDirectories)
struct RunOnlyHookTests {
    private static var file: String {
        ListedWideWindowTests.file
    }

    /// Runs the built hook with `arguments` on `payload` in `root`, every state path under `home`: its exit status and what it printed.
    private static func run(_ arguments: [String], payload: [String: Any], in root: URL, home: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> (status: Int32, printed: String) {
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
        environment["SWIFT_SURE_TEST_INPLACE_BUDGET"] = "60"
        environment["SWIFT_SURE_TEST_HOOK_BUDGET"] = "60"
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: payload))
        input.fileHandleForWriting.closeFile()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: printed, encoding: .utf8) ?? "")
    }

    /// A `PreToolUse` payload for `call` made in `root`.
    private static func payload(_ call: Call, in root: URL, session: String) -> [String: Any] {
        let (tool, input) = call.call(in: root)
        return payload(tool, input, in: root, session: session)
    }

    private static func payload(_ tool: String, _ input: [String: Any], in root: URL, session: String, mode: String = "default") -> [String: Any] {
        ["session_id": session, "cwd": root.path, "hook_event_name": "PreToolUse", "permission_mode": mode, "transcript_path": "", "tool_name": tool, "tool_input": input, "tool_use_id": "toolu-\(session)"]
    }

    /// Every file of advice state the hook has written under `home`, relative to it: the advice directory (the ledger, `suppressions.jsonl`) and the usage log.
    private static func adviceState(in home: URL) -> [String] {
        let advice = home.appendingPathComponent("advice")
        let files = (FileManager.default.enumerator(atPath: advice.path)?.allObjects as? [String] ?? [])
            .filter { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: advice.appendingPathComponent(name).path, isDirectory: &isDirectory) && !isDirectory.boolValue
            }
            .map { "advice/\($0)" }
        let usage = FileManager.default.fileExists(atPath: home.appendingPathComponent("usage.jsonl").path) ? ["usage.jsonl"] : []
        return (files + usage).sorted()
    }

    /// A call the plain hook answers or notes is let through by the run-only hook with nothing printed and nothing written to the advice state.
    @Test(arguments: Call.allCases)
    func aCallThePlainHookActsOnIsSilentAndUnnoted(call: Call) throws {
        let root = try ListedWideWindowTests.repository()
        let plainHome = try TemporaryDirectory.make("plain-\(call)")
        let plain = try Self.run(["pre-tool-use"], payload: Self.payload(call, in: root, session: "plain-\(call)"), in: root, home: plainHome)
        try #require(
            !plain.printed.isEmpty || !Self.adviceState(in: plainHome).isEmpty,
            "the plain hook neither answered nor noted \(call), so its silence under --run-only pins nothing"
        )

        let home = try TemporaryDirectory.make("run-only-\(call)")
        let runOnly = try Self.run(["pre-tool-use", "--run-only"], payload: Self.payload(call, in: root, session: "run-only-\(call)"), in: root, home: home)

        #expect(runOnly.status == 0)
        #expect(runOnly.printed.isEmpty, "printed: \(runOnly.printed)")
        #expect(Self.adviceState(in: home).isEmpty)
    }

    /// One context's calls in a row, each run-only, leave no advice state behind: no ledger, no suppression row, no usage line.
    @Test
    func aRunOfLookupsLeavesNoAdviceState() throws {
        let root = try ListedWideWindowTests.repository()
        let home = try TemporaryDirectory.make("run-only-sequence")
        var printed: [String] = []
        for call in Call.allCases {
            let ran = try Self.run(["pre-tool-use", "--run-only"], payload: Self.payload(call, in: root, session: "run-only-sequence"), in: root, home: home)
            #expect(ran.status == 0)
            printed.append(ran.printed)
        }

        let answered = printed.filter { !$0.isEmpty }

        #expect(answered.isEmpty, "printed: \(answered)")
        #expect(Self.adviceState(in: home).isEmpty)
    }

    /// The run-only hook rewrites a `swift test` into `swift-sure run --` where nobody is asked, exactly as the plain hook does.
    @Test
    func aSwiftTestIsRewrittenAsThePlainHookRewritesIt() throws {
        let root = try ListedWideWindowTests.repository()
        try "// swift-tools-version:6.0\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])\n"
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let test = Self.payload("Bash", ["command": "swift test --filter Gizmo"], in: root, session: "run-only-test", mode: "auto")

        let runOnly = try Self.run(["pre-tool-use", "--run-only"], payload: test, in: root, home: TemporaryDirectory.make("run-only-test"))
        let plain = try Self.run(["pre-tool-use"], payload: test, in: root, home: TemporaryDirectory.make("plain-test"))

        #expect(runOnly.status == 0)
        #expect(runOnly.printed.contains("\"command\":\"swift-sure run -- swift test --filter Gizmo\""))
        #expect(runOnly.printed == plain.printed)
    }
}

extension RunOnlyHookTests {
    /// A call the plain hook acts on, by printing an answer or by noting it in the advice state.
    enum Call: String, CaseIterable, CustomTestStringConvertible {
        case read
        case cat
        case sedWindow
        case head
        case otherRevision
        case digest
        case write
        case edit

        var testDescription: String {
            rawValue
        }

        /// The tool and its input, for a call made in `root`.
        func call(in root: URL) -> (tool: String, input: [String: Any]) {
            let path = root.appendingPathComponent(RunOnlyHookTests.file).path
            return switch self {
            case .read: ("Read", ["file_path": path])
            case .cat: ("Bash", ["command": "cat \(RunOnlyHookTests.file)"])
            case .sedWindow: ("Bash", ["command": "sed -n 1,50p \(RunOnlyHookTests.file)"])
            case .head: ("Bash", ["command": "head -400 \(RunOnlyHookTests.file)"])
            case .otherRevision: ("Bash", ["command": "git grep balance1 HEAD -- '*.swift'"])
            case .digest: ("mcp__swift-sure__digest", ["target": "Ledger", "root": root.path])
            case .write: ("Write", ["file_path": root.appendingPathComponent("Sources/App/Gizmo.swift").path, "content": "struct Gizmo {}\n"])
            case .edit: ("Edit", ["file_path": path, "old_string": "/// The ledger.", "new_string": "/// The gizmo ledger."])
            }
        }
    }
}
