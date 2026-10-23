//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A suite whose type is a raw identifier (`` `a.b` ``, `` `a/b` ``): one unit however many dots or slashes its name holds.
struct PackageShardRawSuiteTests {
    private static func test(_ listed: String) -> TestIdentifier {
        ((try? PackageShardPlanner.listed(listed)) ?? []).first ?? ((try? PackageShardPlanner.listed("Invalid.Invalid/invalid()")) ?? [])[0]
    }

    @Test func aDottedRawIdentifierSuiteIsOneUnitWithItsNestedSuites() {
        #expect(PackageShardPlanner.suite(of: Self.test("LibTests.`a.b`/test()")) == "LibTests.`a.b`")
        #expect(PackageShardPlanner.suite(of: Self.test("LibTests.`a.b`.Inner/test()")) == "LibTests.`a.b`")
        #expect(PackageShardPlanner.suite(of: Self.test("LibTests.Outer.`a.b`/test()")) == "LibTests.Outer")
    }

    @Test func theFilterStillSelectsARawIdentifierSuite() throws {
        let tests = [Self.test("LibTests.`a.b`/test()"), Self.test("LibTests.`a.b`.Inner/other()")]
        let pattern = PackageShardPlanner.filter(for: tests)
        let regex = try NSRegularExpression(pattern: pattern)

        #expect(pattern == #"^(?:LibTests\.`a\.b`)[/.]"#)
        #expect(regex.firstMatch(in: "LibTests.`a.b`/test()", range: NSRange(location: 0, length: 21)) != nil)
    }
}
