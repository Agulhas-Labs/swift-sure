//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// The access verdict `diff` reaches from the uses found for one declaration.
struct DiffAccessJudgePinsTests {
    private typealias Use = AccessJudge.Use

    private static let tool = Use(path: "Sources/GizmoTools/Tool.swift", module: "GizmoTools")
    private static let testFile = Use(path: "Tests/GizmoTests/GizmoTests.swift", module: "GizmoTests")

    private static func packages(version: [Int]? = [5, 10], members: [String: String] = ["GizmoKit": "", "GizmoTools": "", "GizmoTests": ""]) -> AccessPackages {
        AccessPackages(packageOf: members, toolsVersion: version.map { ["": $0] } ?? [:], published: [])
    }

    private static func verdict(
        level: AccessLevel = .publicLevel,
        uses: [Use],
        testable: Set<String>? = nil,
        packages: AccessPackages = packages(),
        exposedAt: AccessLevel? = nil
    ) -> AccessFinding.Verdict {
        AccessJudge.verdict(
            level: level,
            module: "GizmoKit",
            uses: uses,
            testableImports: { $0 == testFile.path ? testable : nil },
            packages: packages,
            exposedAt: exposedAt
        )
    }

    @Test func noUseOutsideTheModuleSuggestsInternal() {
        let verdict = Self.verdict(uses: [Use(path: "Sources/GizmoKit/Own.swift", module: "GizmoKit")])

        #expect(verdict == .noUse(testable: false))
        #expect(verdict.suggestion == .internalLevel)
    }

    @Test func aDeclarationUsedOnlyFromTestsImportingTheModuleTestableSuggestsInternal() {
        let verdict = Self.verdict(uses: [Self.testFile], testable: ["GizmoKit"])

        #expect(verdict == .noUse(testable: true))
        #expect(verdict.suggestion == .internalLevel)
    }

    @Test func aTestImportingTheModulePlainlyIsAUseFromItsPackage() {
        #expect(Self.verdict(uses: [Self.testFile], testable: []) == .packageOnly(users: ["GizmoTests"]))
        let elsewhere = Self.packages(members: ["GizmoKit": "", "GizmoTests": "Other"])
        #expect(Self.verdict(uses: [Self.testFile], testable: [], packages: elsewhere) == .needsLevel)
    }

    @Test func aProductionUseBesideTestableTestsDecidesTheVerdict() {
        let verdict = Self.verdict(uses: [Self.testFile, Self.tool], testable: ["GizmoKit"])

        #expect(verdict == .packageOnly(users: ["GizmoTools"]))
    }

    @Test func usesFromAnotherModuleOfTheSamePackageSuggestPackage() {
        let verdict = Self.verdict(uses: [Self.tool])

        #expect(verdict == .packageOnly(users: ["GizmoTools"]))
        #expect(verdict.suggestion == .packageLevel)
    }

    @Test func noPackageSuggestionWhereTheRepositoryIsNotASwiftPMPackage() {
        let none = Self.packages(version: nil, members: [:])

        #expect(Self.verdict(uses: [Self.tool], packages: none) == .needsLevel)
    }

    @Test func noPackageSuggestionBelowToolsVersionFiveNine() {
        #expect(Self.verdict(uses: [Self.tool], packages: Self.packages(version: [5, 8])) == .needsLevel)
        #expect(Self.verdict(uses: [Self.tool], packages: Self.packages(version: [5, 9])) == .packageOnly(users: ["GizmoTools"]))
    }

    @Test func noPackageSuggestionWhereAUsingModuleIsInAnotherPackage() {
        let split = Self.packages(members: ["GizmoKit": "", "GizmoTools": "Tools"])

        #expect(Self.verdict(uses: [Self.tool], packages: split) == .needsLevel)
    }

    @Test func aPackageLevelDeclarationUsedFromAnotherModuleNeedsItsLevel() {
        #expect(Self.verdict(level: .packageLevel, uses: [Self.tool]) == .needsLevel)
    }

    @Test func aUseWhoseModuleIsUnknownCountsAsOutside() {
        let unknown = Use(path: "Sources/Elsewhere/Tool.swift", module: nil)

        #expect(Self.verdict(uses: [unknown]) == .needsLevel)
        #expect(Self.verdict(uses: [unknown, Self.tool]) == .needsLevel)
        #expect(Self.verdict(level: .packageLevel, uses: [unknown]) == .needsLevel)
    }

    @Test func aDeclarationAWiderOneExposesIsNeverSuggestedBelowThatLevel() {
        #expect(Self.verdict(uses: [], exposedAt: .publicLevel) == .needsLevel)
        #expect(Self.verdict(uses: [Self.tool], exposedAt: .publicLevel) == .needsLevel)
        #expect(Self.verdict(uses: [], exposedAt: .internalLevel) == .noUse(testable: false))
        #expect(Self.verdict(uses: [Self.tool], exposedAt: .packageLevel) == .packageOnly(users: ["GizmoTools"]))
    }
}
