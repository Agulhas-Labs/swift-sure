//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// The `checkup` answer frame as a pure function of its inputs: each check named once, findings in class order, twenty to a page.
struct CheckupFrameRenderingTests {
    private static var header: String {
        "tree: app  head: 3f2a9c1  clean  semantic: fresh"
    }

    private static var range: String {
        "main...HEAD — HEAD against its merge-base with main, 81c0d2e"
    }

    private static func finding(_ kind: CheckupFindingClass, path: String? = "Sources/App/Gizmo.swift", line: Int? = 1, text: String = "text") -> CheckupFinding {
        CheckupFinding(findingClass: kind, path: path, line: line, endLine: nil, text: text, command: "swift-sure diff")
    }

    private static func render(_ findings: [CheckupFinding], checks: CheckupChecks = .unbuilt, offset: Int = 0) -> [String] {
        CheckupRenderer(header: header, range: range, changedFiles: 4, findings: findings, checks: checks, offset: offset)
            .render()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func checkedEverywhere() -> CheckupChecks {
        CheckupChecks(Dictionary(uniqueKeysWithValues: CheckupCheck.allCases.map { ($0, .checked(basis: nil, bound: nil)) }))
    }

    /// Every check is named on exactly one of the two lists, whatever the mix of statuses.
    @Test
    func everyCheckIsNamedOnExactlyOneList() throws {
        var statuses = Self.checkedEverywhere().statuses
        statuses[.coverage] = .notChecked(reason: "none recorded")
        statuses[.callers] = .checked(basis: "store open", bound: nil)
        statuses[.flakyTests] = nil

        let line = try #require(Self.render([], checks: CheckupChecks(statuses)).dropFirst(2).first)
        let parts = line.components(separatedBy: " · ")
        let checked = try #require(parts.first { $0.hasPrefix("checked: ") })
        let unchecked = try #require(parts.first { $0.hasPrefix("not checked: ") })

        for check in CheckupCheck.allCases {
            let mentions = [checked, unchecked].filter { $0.contains(check.name) }.count
            #expect(mentions == 1, "\(check.name) is named \(mentions) times")
        }

        #expect(unchecked.contains("flaky tests (no status reported)"))
    }

    /// A check a bound stopped part way ran, so it is on `checked:`, with what was left out counted.
    @Test
    func aBoundedCheckIsCheckedWithItsCount() throws {
        var statuses = CheckupChecks.unbuilt.statuses
        statuses[.callers] = .checked(basis: nil, bound: "20 of 25 members; 5 not looked up")

        let line = try #require(Self.render([], checks: CheckupChecks(statuses)).dropFirst(2).first)

        #expect(line.hasPrefix("checked: callers (20 of 25 members; 5 not looked up) · not checked: "))
        #expect(!line.components(separatedBy: " · ")[1].contains("callers"))
    }

    /// With nothing built, the frame says so for each of the six and finds nothing.
    @Test
    func anUnbuiltCheckIsNotCheckedWithItsReason() {
        let lines = Self.render([])

        #expect(lines[0] == Self.header)
        #expect(lines[1] == "checkup: \(Self.range) · nothing found over 4 changed files")
        #expect(lines[2].hasPrefix("not checked: callers (not built yet), test runs (not built yet)"))
        #expect(lines.count == 3)
    }

    /// Classes keep their fixed order across checks, then path and line within a class.
    @Test
    func classOrderHoldsAcrossChecks() {
        let lines = Self.render([
            Self.finding(.duplicate),
            Self.finding(.callers, path: "B.swift", line: 9),
            Self.finding(.failed, path: nil, line: nil),
            Self.finding(.callers, path: "A.swift", line: 30),
            Self.finding(.callers, path: "A.swift", line: 4),
            Self.finding(.unproved, path: nil, line: nil),
        ])

        let order = lines.dropFirst(3).compactMap { $0.split(separator: " ").first.map(String.init) }
        let locations = lines.dropFirst(3).filter { $0.hasPrefix("callers") }.compactMap { $0.split(separator: " ").dropFirst().first.map(String.init) }

        #expect(order == ["failed", "callers", "callers", "callers", "unproved", "duplicate"])
        #expect(locations == ["A.swift:4", "A.swift:30", "B.swift:9"])
        #expect(lines[1].hasSuffix("6 findings over 4 changed files — 1 failed, 3 callers, 1 unproved, 1 duplicate"))
    }

    /// The 21st finding is on the next page, counted, and the marker names the offset that reaches it.
    @Test
    func theTwentyFirstFindingIsOnTheNextPageAndCounted() {
        let findings = (1 ... 21).map { Self.finding(.callers, line: $0) }

        let first = Self.render(findings)
        let second = Self.render(findings, offset: 20)

        #expect(first.filter { $0.hasPrefix("callers") }.count == 20)
        #expect(first.last == "truncated: 1 more finding — pass --offset 20")
        #expect(second.filter { $0.hasPrefix("callers") }.count == 1)
        #expect(second.last?.hasSuffix("Sources/App/Gizmo.swift:21  text — swift-sure diff") == true)
    }

    /// A later page carries the header, its page of how many, and findings only.
    @Test
    func aLaterPageCarriesOnlyFindingsAndItsPageNumber() {
        let findings = (1 ... 45).map { Self.finding(.callers, line: $0) }

        let lines = Self.render(findings, offset: 20)

        #expect(lines[0] == Self.header)
        #expect(lines[1] == "checkup: page 2 of 3 — 45 findings")
        #expect(!lines.contains { $0.hasPrefix("checked:") || $0.hasPrefix("not checked:") })
        #expect(lines.filter { $0.hasPrefix("callers") }.count == 20)
        #expect(lines.last == "truncated: 5 more findings — pass --offset 40")
    }

    /// A span prints as first-last, and a finding with no place prints its text alone.
    @Test
    func aSpanAndAPlacelessFindingPrint() {
        let span = CheckupFinding(findingClass: .duplicate, path: "Sources/App/Gizmo.swift", line: 60, endLine: 88, text: "pair", command: "swift-sure similar Gizmo.wobble")
        let lines = Self.render([span, Self.finding(.unproved, path: nil, line: nil, text: "no run")])

        #expect(lines.contains("unproved   no run — swift-sure diff"))
        #expect(lines.contains("duplicate  Sources/App/Gizmo.swift:60-88  pair — swift-sure similar Gizmo.wobble"))
    }
}
