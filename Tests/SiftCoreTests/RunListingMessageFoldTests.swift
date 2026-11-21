//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// A listing says a long message or value once across its failures: the same message of several tests, and a long value one test printed above.
struct RunListingMessageFoldTests {
    private static let uuids = [
        "C81E6005-B078-4140-9D99-09079F392D16", "D55FC4C8-5429-42B5-B9FD-B2ABFD6BCE13", "DE89DEEC-5B97-4A29-8A18-4238E41326EE",
    ]

    /// The three caught errors of the sample differ in a directory's UUID and an address: the first prints, the others point at it.
    @Test
    func threeCaughtErrorsDifferingInUUIDsAndAddressesSayItOnce() {
        let block = Self.listing([
            Self.caught("beta()", "P.swift:8:2", uuid: Self.uuids[0], address: "0x104bb6c60"),
            Self.caught("gamma()", "P.swift:9:2", uuid: Self.uuids[1], address: "0x104bacb70"),
            Self.caught("alpha()", "P.swift:7:2", uuid: Self.uuids[2], address: "0x104bb6c30"),
        ])
        let clause = "(the same message line as under beta() at P.swift:8:2 above, but for its temporary directories' UUIDs and object addresses)"

        #expect(block.contains("    " + Self.caught("beta()", "P.swift:8:2", uuid: Self.uuids[0], address: "0x104bb6c60").message))
        #expect(block.filter { $0 == "    " + clause }.count == 2)
        #expect(block.filter { $0.hasPrefix("    Caught error") }.count == 1)
        #expect(block.contains("  gamma() — P.swift:9:2") && block.contains("  alpha() — P.swift:7:2"))
    }

    /// Exactly equal messages carry no clause, and only the kinds that differed are named.
    @Test
    func theClauseNamesOnlyWhatDiffered() {
        let equal = Self.listing([
            Self.caught("a()", "P.swift:1:1", uuid: Self.uuids[0], address: "0x104bb6c60"),
            Self.caught("b()", "P.swift:2:1", uuid: Self.uuids[0], address: "0x104bb6c60"),
        ])
        let uuidOnly = Self.listing([
            Self.caught("a()", "P.swift:1:1", uuid: Self.uuids[0], address: "0x104bb6c60"),
            Self.caught("b()", "P.swift:2:1", uuid: Self.uuids[1], address: "0x104bb6c60"),
        ])
        let addressOnly = Self.listing([
            Self.caught("a()", "P.swift:1:1", uuid: Self.uuids[0], address: "0x104bb6c60"),
            Self.caught("b()", "P.swift:2:1", uuid: Self.uuids[0], address: "0x104bb6c61"),
        ])

        #expect(equal.contains("    (the same message line as under a() at P.swift:1:1 above)"))
        #expect(uuidOnly.contains("    (the same message line as under a() at P.swift:1:1 above, but for its temporary directories' UUIDs)"))
        #expect(addressOnly.contains("    (the same message line as under a() at P.swift:1:1 above, but for its object addresses)"))
    }

    /// Two errors that differ in a code, or a message of 240 or fewer bytes, are printed in full.
    @Test
    func aDifferingCodeOrAShortMessageIsPrintedTwice() {
        let codes = Self.listing([
            Self.caught("a()", "P.swift:1:1", uuid: Self.uuids[0], address: "0x104bb6c60"),
            Self.caught("b()", "P.swift:2:1", uuid: Self.uuids[0], address: "0x104bb6c60", code: 4),
        ])
        let short = Self.listing([
            Self.failure("a()", "P.swift:1:1", message: "Caught error: short"),
            Self.failure("b()", "P.swift:2:1", message: "Caught error: short"),
        ])

        #expect(codes.filter { $0.hasPrefix("    Caught error") }.count == 2)
        #expect(short.filter { $0 == "    Caught error: short" }.count == 2)
    }

    /// A status code a test compared is no address, and a simulator's device UUID is not read.
    @Test
    func aComparedCodeAndASimulatorDevicePathAreNotMasked() {
        let padding = String(repeating: "x", count: 250)
        let compared = Self.listing([
            Self.failure("a()", "P.swift:1:1", message: "\(padding) status=0x80070005 and 0x80070005"),
            Self.failure("b()", "P.swift:2:1", message: "\(padding) status=0x80070006 and 0x80070005"),
        ])
        let device = "/Users/u/Library/Developer/CoreSimulator/Devices/"
        let simulator = Self.listing(Self.uuids.prefix(2).enumerated().map { offset, uuid in
            Self.failure("t\(offset)()", "P.swift:\(offset + 1):1", message: "\(padding) NSFilePath=\(device)\(uuid)/data/tmp/x")
        })

        let checksums = Self.listing([
            Self.failure("c()", "P.swift:3:1", message: "\(padding) checksum=0x1a2b3c4d5e6f7a8b"),
            Self.failure("d()", "P.swift:4:1", message: "\(padding) checksum=0xffffffffffffffff"),
        ])

        #expect(checksums.filter { $0.contains("checksum=") }.count == 2)
        #expect(compared.filter { $0.contains("status=") }.count == 2)
        #expect(simulator.filter { $0.contains("CoreSimulator") }.count == 2)
    }

    /// One directory named twice never matches a message naming two, and the nearest printed match is the target.
    @Test
    func theRenamingIsConsistentAndTheNearestPrintedMatchIsTheTarget() {
        func message(_ first: String, _ second: String) -> String {
            let padding = String(repeating: "x", count: 250)
            return "\(padding) /var/folders/ab/T/p-\(first)/f /var/folders/ab/T/p-\(second)/g"
        }
        let block = Self.listing([
            Self.failure("a()", "P.swift:1:1", message: message(Self.uuids[0], Self.uuids[0])),
            Self.failure("b()", "P.swift:2:1", message: message(Self.uuids[0], Self.uuids[1])),
            Self.failure("c()", "P.swift:3:1", message: message(Self.uuids[1], Self.uuids[1])),
            Self.failure("d()", "P.swift:4:1", message: message(Self.uuids[2], Self.uuids[2])),
        ])
        let uuidsClause = "above, but for its temporary directories' UUIDs)"

        #expect(block.filter { $0.contains("/var/folders") }.count == 2)
        #expect(block.contains("    (the same message line as under a() at P.swift:1:1 \(uuidsClause)"))
        // A message equal to the first once masked points at the first, not the second; a folded failure is no target.
        #expect(block.contains("    (the same message line as under b() at P.swift:2:1 \(uuidsClause)") == false)
        #expect(block.filter { $0.hasPrefix("    (the same message line") }.count == 2)
    }

    /// A message equal to an earlier printed one up to a UUID names the nearest such, with no clause where the nearest is exactly equal.
    @Test
    func aMessageEqualToTheNearestPrintedOneCarriesNoClause() {
        let block = Self.listing([
            Self.caught("a()", "P.swift:1:1", uuid: Self.uuids[0], address: "0x104bb6c60"),
            Self.caught("b()", "P.swift:2:1", uuid: Self.uuids[1], address: "0x104bb6c60"),
            Self.caught("c()", "P.swift:3:1", uuid: Self.uuids[0], address: "0x104bb6c60"),
        ])

        #expect(block.contains("    (the same message line as under a() at P.swift:1:1 above)"))
        #expect(block.contains("    (the same message line as under a() at P.swift:1:1 above, but for its temporary directories' UUIDs)"))
    }

    /// A stream-read or unlocated failure is never folded.
    @Test
    func streamReadAndUnlocatedFailuresAreNeverFolded() {
        let message = Self.caught("a()", "P.swift:1:1", uuid: Self.uuids[0], address: "0x104bb6c60").message
        let block = Self.listing([
            Self.failure("a()", "P.swift:1:1", message: message),
            Self.failure("b()", nil, message: message),
            RunFailureShape.Failure(name: "c()", location: "P.swift:3:1", message: message, readFromStream: true),
        ])

        #expect(block.filter { $0.hasPrefix("    Caught error") }.count == 3)
    }

    /// The second and third `many()` failures say the `gizmoNames` value once, where the first printed it.
    @Test
    func aLongValueOfOneTestIsPrintedOnce() {
        let block = Self.listing((12 ... 14).map { Self.many(line: $0) })
        let pointer = "gizmoNames → (the value printed under many() at P.swift:12:5 above)"

        #expect(block.filter { $0.hasSuffix(pointer) }.count == 2)
        #expect(block.filter { $0.contains("gizmo-step-0-with") }.count == 1)
        #expect(block.contains { $0.hasPrefix("    Expectation failed: !gizmoNames.contains(\"gizmo-step-3") && $0.contains("gizmoNames.contains(\"gizmo-step-3-with-a-longish-name\") → false \(pointer)") })
    }

    /// A pointer never names a value the earlier line's cap cut away, and another test's identical piece is not folded.
    @Test
    func aPointerNeverNamesCutTextOrAnotherTest() {
        let long = "[" + (0 ..< 40).map { "\"item-\($0)\"" }.joined(separator: ", ") + "]"
        let cutting = String(repeating: "y", count: 1000)
        let first = Self.failure("many()", "P.swift:1:1", message: "Expectation failed: \(cutting)", markedLines: ["\(cutting) → true", "gizmoNames → \(long)"])
        let second = Self.failure("many()", "P.swift:2:1", message: "Expectation failed: okay", markedLines: ["okay → true", "gizmoNames → \(long)"])
        let other = Self.failure("other()", "P.swift:3:1", message: "Expectation failed: fine", markedLines: ["fine → true", "gizmoNames → \(long)"])

        #expect(Self.listing([first, second]).contains { $0.contains("(the value printed") } == false)
        let shown = Self.failure("many()", "P.swift:1:1", message: "Expectation failed: ok", markedLines: ["ok → true", "gizmoNames → \(long)"])
        #expect(Self.listing([shown, other]).contains { $0.contains("(the value printed") } == false)
        #expect(Self.listing([shown, second]).contains { $0.contains("(the value printed under many() at P.swift:1:1 above)") })
    }

    // MARK: Fixtures

    static func listing(_ failures: [RunFailureShape.Failure]) -> [String] {
        RunFailureShape.of(failures, changedFiles: .of([])).rendered()
    }

    static func failure(_ name: String, _ location: String?, message: String, markedLines: [String] = []) -> RunFailureShape.Failure {
        let note = markedLines.isEmpty ? nil : markedLines.joined(separator: " ")
        return RunFailureShape.Failure(name: name, location: location, message: message, note: note, markedLines: markedLines.enumerated().map { ($0.offset == 0 ? "" : "  ") + $0.element })
    }

    static func caught(_ name: String, _ location: String, uuid: String, address: String, code: Int = 260) -> RunFailureShape.Failure {
        let path = "/var/folders/2j/s9y9crq145d8zn8ktvdpxrlm0000gn/T/probe-tests-\(uuid)/default.2.json"
        let message = "Caught error: Error Domain=NSCocoaErrorDomain Code=\(code) \"The file “default.2.json” couldn’t be opened because there is no such file.\" "
            + "UserInfo={NSFilePath=\(path), NSURL=file://\(path), NSUnderlyingError=\(address) {Error Domain=NSPOSIXErrorDomain Code=2 \"No such file or directory\"}}"
        return failure(name, location, message: message)
    }

    static func many(line: Int) -> RunFailureShape.Failure {
        let value = "[" + (0 ..< 30).map { "\"gizmo-step-\($0)-with-a-longish-name\"" }.joined(separator: ", ") + "]"
        let step = line - 10
        let expression = "!gizmoNames.contains(\"gizmo-step-\(step)-with-a-longish-name\")"
        let inner = "gizmoNames.contains(\"gizmo-step-\(step)-with-a-longish-name\")"
        let marked = ["\(expression) → true", "\(inner) → false", "gizmoNames → \(value)"]
        return failure("many()", "P.swift:\(line):5", message: "Expectation failed: \(expression)", markedLines: marked)
    }
}
