//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// `swift sure …`, which SwiftPM's `swift` driver forwards to the `swift-sure` executable, is one more spelling of the tool's own name wherever a command's words are matched against it.
struct DriverSpellingTests {
    private static func bash(_ command: String) -> Data {
        TranscriptFixture.toolUse("Bash", input: ["command": command])
    }

    @Test
    func theDriverFormIsOneMoreSpellingOfTheBinary() {
        #expect(ProductName.current.driverSpelling == ["swift", "sure"])
        #expect(ProductName.legacy[0].driverSpelling == nil)
        #expect(ProductName.binarySpellingLength(of: ["swift", "sure", "where", "Depot"]) == 2)
        #expect(ProductName.binarySpellingLength(of: ["swift-sure", "where", "Depot"]) == 1)
        #expect(ProductName.binarySpellingLength(of: ["/x/swift-sure", "where", "Depot"]) == 1)
        #expect(ProductName.binarySpellingLength(of: ["sift", "where", "Depot"]) == 1)
        #expect(ProductName.binarySpellingLength(of: ["swift", "build"]) == nil)
        #expect(ProductName.binarySpellingLength(of: ["swift", "run", "Gizmo"]) == nil)
        #expect(ProductName.binarySpellingLength(of: ["swift", "suresh"]) == nil)
        #expect(ProductName.binarySpellingLength(of: ["swift"]) == nil)
        #expect(ProductName.binarySpellingLength(of: []) == nil)
        #expect(ProductName.binarySpellingLength(of: ["swift", "sure"], recognising: [ProductName(word: "gizmo", displayName: "Gizmo")]) == nil)
        #expect(ProductName.binarySpellingLength(of: ["swift", "gizmo"], recognising: [ProductName(word: "swift-gizmo", displayName: "Gizmo")]) == 2)
    }

    @Test
    func theBinaryPrefixIsRemovedInTheDriverSpellingToo() {
        #expect(ProductName.removingBinary(from: "swift sure digest Depot") == "digest Depot")
        #expect(ProductName.removingBinary(from: "swift-sure digest Depot") == "digest Depot")
        #expect(ProductName.removingBinary(from: "swift suresh digest Depot") == nil)
        #expect(ProductName.removingBinary(from: "swift build") == nil)
    }

    @Test
    func aSegmentRunningTheDriverFormInvokesTheTool() {
        for command in ["swift sure where Depot", "swift-sure where Depot", "/x/swift-sure where Depot", "sift where Depot", "FOO=1 swift sure where Depot"] {
            #expect(ShellQuery(command).invokesSift, "\(command)")
        }
        for command in ["swift build", "swift run Gizmo", "swift suresh", #"grep -rn "swift sure" Sources"#] {
            #expect(!ShellQuery(command).invokesSift, "\(command)")
        }

        #expect(ShellQuery("swift sure where Depot").wordsAfterBinary() == ["where", "Depot"])
        #expect(ShellQuery("swift-sure where Depot").wordsAfterBinary() == ["where", "Depot"])
        #expect(ShellQuery("swift build").wordsAfterBinary() == nil)
    }

    @Test
    func aRunInTheDriverFormIsNotWrappedAgain() {
        #expect(RunAdvice.suggestion(for: "swift sure run -- swift test && swift build") == nil)
        #expect(RunAdvice.suggestion(for: "swift-sure run -- swift test && swift build") == nil)
        #expect(RunAdvice.suggestion(for: "swift test") != nil)
    }

    @Test(.temporaryDirectories)
    func aRunInTheDriverFormClearsTheEditsBeforeIt() throws {
        // A directory whose name carries no binary name, so only the command's own words can pass the transcript prefilter.
        let repo = try MCPTestRepo.make(at: TemporaryDirectory.make("mcp", prefix: "neutral"), declaring: "Gauge")
        #expect(!repo.path.contains("sure") && !repo.path.contains("sift"))
        let gauge = repo.appendingPathComponent("Sources/App/Gauge.swift").path
        let lines: [Data] = [
            TranscriptFixture.toolUse("Edit", id: "e1", input: ["file_path": gauge], cwd: repo.path),
            TranscriptFixture.toolResult(id: "e1", isError: false),
            TranscriptFixture.toolUse("Bash", id: "b1", input: ["command": "swift sure run -- swift build"], cwd: repo.path),
            TranscriptFixture.toolResult(id: "b1", isError: false),
        ]
        let directory = try TemporaryDirectory.make("driver-runs")
        let transcript = directory.appendingPathComponent("session.jsonl")
        try Data(lines.flatMap { $0 + [0x0A] }).write(to: transcript)

        let scanned = BuildInputEditsSinceGreenRun.scan(transcript: transcript, skippingSidechains: false)

        #expect(scanned?.files == [])
    }

    @Test
    func aLookupInTheDriverFormCountsInTheTranscriptScan() {
        let hyphenated = TranscriptFixture.tally([Self.bash("swift-sure digest Depot")])
        let driver = TranscriptFixture.tally([Self.bash("swift sure digest Depot")])

        #expect(driver.indexed == 1)
        #expect(driver.cliCalls == 1)
        #expect(driver.total == 1)
        #expect(driver.indexed == hyphenated.indexed)
        #expect(driver.cliCalls == hyphenated.cliCalls)
    }

    @Test
    func aDriverFormDigestNamesItsTargets() {
        let found = IndexCallTarget.cliDigests(inCommand: "swift sure digest Depot Gizmo > out.txt")

        #expect(found.map(\.target) == ["Depot", "Gizmo"])
        #expect(IndexCallTarget.documentDigest(inCommand: "swift sure digest README.md"))
    }

    @Test
    func aDriverFormCallIsRowedAndCreditedLikeTheHyphenatedOne() {
        let opening = InPlaceAnswer.openingLine(calls: ["swift sure digest Sources/App/Gizmo.swift"])

        let call = AuditVerbs.call(name: "Read", input: ["file_path": "/r/Sources/App/Gizmo.swift"], answerText: opening + "\n\nbody", refused: true)
        let arguments = AuditVerbs.siftArguments(of: ShellQuery("swift sure where Depot > log"))

        #expect(call?.kind == "digest (file) (hook)")
        #expect(Array(arguments) == ["where", "Depot"])
        #expect(AnswerThenRead.digestTarget(of: "swift sure digest Sources/App/Gizmo.swift") == "Sources/App/Gizmo.swift")
    }

    @Test
    func aCallShapeKeepsTheDriverFormAsWritten() {
        #expect(ContextReplay.shaped("swift sure digest Depot") == "swift sure digest <text>")
        #expect(ContextReplay.shaped("swift-sure digest Depot") == "swift-sure digest <text>")
    }

    @Test
    func aDriverFormLookupIsReadLikeTheHyphenatedOne() {
        #expect(IndexCallTarget.cliLookups(inCommand: "swift sure where Depot") == [["where", "Depot"]])
        #expect(IndexCallTarget.cliLookups(inCommand: "swift-sure where Depot") == [["where", "Depot"]])
        #expect(IndexCallTarget.cliLookups(inCommand: "swift sure where Depot > out.txt") == [["where", "Depot"]])
        #expect(IndexCallTarget.cliLookups(inCommand: "swift sure run -- swift build").isEmpty)
    }

    @Test
    func aDriverFormLookupIsRecordedAsMadeLikeTheHyphenatedOne() {
        let hyphenated = IndexSuggestion.callsMade(toolName: "Bash", input: [:], command: "swift-sure where Depot", root: "/r")
        let driver = IndexSuggestion.callsMade(toolName: "Bash", input: [:], command: "swift sure where Depot", root: "/r")

        #expect(!hyphenated.isEmpty)
        #expect(driver == hyphenated)
    }

    @Test(.temporaryDirectories)
    func aDriverFormLookupCreditsTheFilesItLocated() throws {
        let repo = try MCPTestRepo.make(declaring: "Gauge")

        #expect(ShellAnswerSource.of(command: "swift-sure where Gauge", cwd: repo.path) != nil)
        #expect(ShellAnswerSource.of(command: "swift sure where Gauge", cwd: repo.path)?.root == ShellAnswerSource.of(command: "swift-sure where Gauge", cwd: repo.path)?.root)
        #expect(ShellAnswerSource.of(command: "swift sure where Gauge | head -5", cwd: repo.path) != nil)
    }

    @Test
    func aCallsStructureNamesTheToolInTheDriverFormToo() {
        #expect(TranscriptAudit.CallRedaction.structure(of: "swift sure where X") == TranscriptAudit.CallRedaction.structure(of: "swift-sure where X"))
        #expect(TranscriptAudit.CallRedaction.structure(of: "swift sure where X").hasSuffix("with swift-sure"))
    }
}
