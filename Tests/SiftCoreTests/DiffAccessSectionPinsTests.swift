//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// How `diff`'s access section renders a gathered report: the verdict line, the lines that follow it and what stays out of every count.
struct DiffAccessSectionPinsTests {
    private typealias Fixtures = AccessPinFixtures

    private static func render(_ findings: [AccessFinding], notJudged: [AccessExclusion: Int] = [:], notChecked: Int = 0) -> [String] {
        AccessSection.lines(AccessReport(findings: findings, notJudged: notJudged, notChecked: notChecked))
    }

    private static func declarationLines(_ lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix("  + ") || $0.hasPrefix("  ~ ") }
    }

    @Test func aWidenedDeclarationIsCountedInItsLevelAndNamedAsWidened() {
        let lines = Self.render([
            Fixtures.finding("restock()"),
            Fixtures.finding("shelve()", widened: true),
        ])

        #expect(lines.contains("access: this range put 2 declarations at public, 2 with no use outside module GizmoKit"))
        #expect(lines.contains("  1 of the public declarations was widened, not added: GizmoKit.shelve()"))
        #expect(lines.contains("  ~ GizmoKit.shelve()  Sources/GizmoKit/Gizmo.swift:2  public → internal: no use outside module GizmoKit"))
        #expect(lines.contains("  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:2  public → internal: no use outside module GizmoKit"))
    }

    @Test func severalWidenedDeclarationsAreNamedOnOneLine() {
        let lines = Self.render([
            Fixtures.finding("restock()", widened: true),
            Fixtures.finding("shelve()", widened: true),
        ])

        #expect(lines.contains("  2 of the public declarations were widened, not added: GizmoKit.restock(), GizmoKit.shelve()"))
    }

    @Test func aHeadingThatMixesResolutionModesNamesTheNameMatchedDeclarations() {
        let lines = Self.render([
            Fixtures.finding("restock()"),
            Fixtures.finding("shelve()", nameMatched: true),
        ])

        #expect(lines.contains("  uses resolved by the index store, except name-matched over the working tree for: GizmoKit.shelve()"))
        #expect(lines.contains("  + GizmoKit.shelve()  Sources/GizmoKit/Gizmo.swift:2  public → internal: no use by that name outside module GizmoKit"))
        #expect(!lines.contains { $0.contains("unused") })
    }

    @Test func aWhollyNameMatchedReportSaysSoOnceAndNeverCallsAnythingUnused() {
        let lines = Self.render([Fixtures.finding("restock()", nameMatched: true)])

        #expect(lines.contains("  uses name-matched over the working tree, which can miss a use through a typealias, a closure or a macro"))
        #expect(!lines.contains { $0.contains("unused") })
    }

    @Test func aPublishedLibraryCarriesTheOnceOnlyNoteAndPhrasesPublicSuggestionsAsQuestions() {
        let lines = Self.render([
            Fixtures.finding("restock()", published: true),
            Fixtures.finding("shelve()", published: true),
            Fixtures.finding("stack()", level: .packageLevel, published: true),
        ])

        let note = "  GizmoKit is a library product this repository publishes: its public API may serve consumers this repository does not contain"

        #expect(lines.count { $0 == note } == 1)
        #expect(lines.contains("  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:2  public → internal?: no use outside module GizmoKit"))
        #expect(lines.contains("  + GizmoKit.stack()  Sources/GizmoKit/Gizmo.swift:2  package → internal: no use outside module GizmoKit"))
    }

    @Test func anUnpublishedModuleCarriesNeitherTheNoteNorTheQuestion() {
        let lines = Self.render([Fixtures.finding("restock()")])

        #expect(!lines.contains { $0.contains("library product") })
        #expect(!lines.contains { $0.contains("?:") })
    }

    @Test func theEleventhCountedDeclarationIsAMoreLineNamingTheRest() {
        let lines = Self.render((1 ... 12).map { Fixtures.finding("gizmo\($0)()") })

        #expect(Self.declarationLines(lines).count == 10)
        #expect(lines.contains("  +2 more: GizmoKit.gizmo11(), GizmoKit.gizmo12()"))
        #expect(lines.contains("access: this range put 12 declarations at public, 12 with no use outside module GizmoKit"))
    }

    @Test func tenCountedDeclarationsNeedNoMoreLine() {
        let lines = Self.render((1 ... 10).map { Fixtures.finding("gizmo\($0)()") })

        #expect(Self.declarationLines(lines).count == 10)
        #expect(!lines.contains { $0.contains("more:") })
    }

    @Test func declarationsPastTheLookupBudgetAreNotCheckedAndInNoCount() {
        let lines = Self.render([Fixtures.finding("restock()")], notChecked: 3)

        #expect(lines.contains("  not checked: 3 more (over the first 50)"))
        #expect(lines.contains("access: this range put 1 declaration at public, 1 with no use outside module GizmoKit"))
        #expect(AccessLookup.lookupCap == 50)
    }

    @Test func theNotJudgedCountsNeverEnterAVerdictCountAndNoneIsListed() {
        let lines = Self.render(
            [Fixtures.finding("restock()")],
            notJudged: [.witness: 2, .override: 1, .objc: 1]
        )

        #expect(lines.contains("access: this range put 1 declaration at public, 1 with no use outside module GizmoKit"))
        #expect(lines.contains("  not judged: 2 protocol witnesses, 1 override, 1 @objc"))
        #expect(Self.declarationLines(lines).count == 1)
    }

    @Test func everyKindInTheNotJudgedLineIsCountedAndNoneIsListed() {
        let everyKind = Dictionary(uniqueKeysWithValues: AccessExclusion.allCases.map { ($0, 1) })
        let lines = Self.render([], notJudged: everyKind)

        #expect(lines == [
            "",
            "access: none of the declarations this range put at open, public or package could be judged",
            "  not judged: 1 protocol witness, 1 open, 1 override, 1 required init, 1 @objc, 1 @inlinable or @usableFromInline, 1 @_spi, 1 dynamic, 1 entry point, 1 reached by the compiler, not by name, 1 macro-generated, invisible to the parser",
        ])
    }

    @Test func theVerdictCountsAreTheSubjectsAndTheDeclarationLinesAreExactlyTheCountedOnes() {
        let lines = Self.render([
            Fixtures.finding("restock()"),
            Fixtures.finding("shelve()", verdict: .noUse(testable: true)),
            Fixtures.finding("stack()", verdict: .packageOnly(users: ["GizmoTools"])),
            Fixtures.finding("pack()", verdict: .needsLevel),
            Fixtures.finding("ship()", verdict: .needsLevel),
        ])

        #expect(lines.contains("access: this range put 5 declarations at public, 2 with no use outside module GizmoKit, 1 used only inside its package"))
        #expect(Self.declarationLines(lines) == [
            "  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:2  public → internal: no use outside module GizmoKit",
            "  + GizmoKit.shelve()  Sources/GizmoKit/Gizmo.swift:2  public → internal: used only from tests, which import it @testable",
            "  + GizmoKit.stack()  Sources/GizmoKit/Gizmo.swift:2  public → package: used only from GizmoTools, in this package",
        ])
    }

    @Test func aDeclarationUsedOnlyFromTestableTestsIsInTheNoUseCount() {
        let lines = Self.render([Fixtures.finding("restock()", verdict: .noUse(testable: true))])

        #expect(lines.contains("access: this range put 1 declaration at public, 1 with no use outside module GizmoKit"))
        #expect(lines.contains("  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:2  public → internal: used only from tests, which import it @testable"))
    }

    @Test func whenEverySubjectHasAUseThatNeedsItsLevelNoDeclarationLineFollows() {
        let lines = Self.render((1 ... 3).map { Fixtures.finding("gizmo\($0)()", verdict: .needsLevel) })

        #expect(lines.contains("access: this range put 3 declarations at public; each has a use that needs its level"))
        #expect(Self.declarationLines(lines).isEmpty)
    }

    @Test func aLevelWhoseSubjectsSpanSeveralModulesSaysOutsideTheirModule() {
        let lines = Self.render([
            Fixtures.finding("restock()"),
            Fixtures.finding("shelve()", module: "WidgetKit"),
            Fixtures.finding("stack()", level: .packageLevel),
        ])

        #expect(lines.contains("access: this range put 2 declarations at public, 2 with no use outside their module; 1 at package, 1 with no use outside module GizmoKit"))
    }

    @Test func aLevelTheRangePutNoneAtIsNotMentioned() {
        let lines = Self.render([Fixtures.finding("stack()", level: .packageLevel)])

        #expect(lines.contains("access: this range put 1 declaration at package, 1 with no use outside module GizmoKit"))
        #expect(!lines.contains { $0.contains("at public") })
    }
}
