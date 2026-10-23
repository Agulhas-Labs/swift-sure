//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Warnings that fold on an elided path say how many different paths they stood for, and a line number after a path keeps two warnings apart.
struct RunWarningPathFoldTests {
    @Test
    func warningsDifferingOnlyInTheirPathNameHowManyPathsFolded() {
        let section = Self.warningsSection(of: [
            "warning: /Users/dev/Widget/Resources/Logo.png: No such file or directory",
            "warning: /Users/dev/Widget/Resources/Font.ttf: No such file or directory",
        ])

        #expect(section == [
            "warnings (2):",
            "  warning: /Users/dev/Widget/Resources/Logo.png: No such file or directory  ×2 (2 paths)",
        ])
    }

    @Test
    func theSamePathTwiceKeepsThePlainCount() {
        // The log reader drops an identical line, so the grouping is fed the diagnostics directly.
        let warning = RunDiagnostic(severity: .warning, message: "/Users/dev/Widget/Resources/Logo.png: No such file or directory")
        let groups = RunWarningSignature.grouped([warning, warning])

        #expect(groups.count == 1)
        #expect(groups.first?.multiplier == "×2")
    }

    @Test
    func anUnlocatedMessageKeepsItsLineAfterTheElidedPath() {
        let section = Self.warningsSection(of: [
            "warning: /a/Gizmo.swift:12: unused",
            "warning: /a/Gizmo.swift:40: unused",
            "warning: /a/Gizmo.swift:40:7: unused",
        ])

        #expect(section.first == "warnings (3):")
        #expect(section.count == 4)
    }

    @Test
    func theSameLineInTwoFilesFoldsAndNamesBothPaths() {
        let section = Self.warningsSection(of: [
            "warning: /a/Gizmo.swift:12: unused",
            "warning: /b/Gizmo.swift:12: unused",
        ])

        #expect(section == ["warnings (2):", "  warning: /a/Gizmo.swift:12: unused  ×2 (2 paths)"])
    }

    @Test
    func aPathSharedByEveryMessageIsNotCounted() {
        let section = Self.warningsSection(of: [
            "warning: /a/Gizmo.png and /s/Shared.png: missing",
            "warning: /b/Gizmo.png and /s/Shared.png: missing",
        ])

        #expect(section == ["warnings (2):", "  warning: /a/Gizmo.png and /s/Shared.png: missing  ×2 (2 paths)"])
    }

    @Test
    func aMessageWithTwoPathsCountsAsOneList() {
        let section = Self.warningsSection(of: [
            "warning: /a/One.png and /b/Two.png: missing",
            "warning: /c/One.png and /d/Two.png: missing",
        ])

        #expect(section == ["warnings (2):", "  warning: /a/One.png and /b/Two.png: missing  ×2 (2 paths)"])
    }
}

private extension RunWarningPathFoldTests {
    /// The warnings section of a build's answer for a log of `lines`.
    static func warningsSection(of lines: [String]) -> [String] {
        var filter = RunOutputFilter(expecting: .unreadable)
        for line in lines {
            filter.consume(line: line)
        }
        let renderer = RunReportRenderer(kind: .swiftBuild, workingDirectory: URL(fileURLWithPath: "/Users/dev/Widget"))
        let answer = renderer.render(filter.finish(), exitCode: 0, logURL: nil).components(separatedBy: "\n")
        guard let start = answer.firstIndex(where: { $0.hasPrefix("warnings (") }) else {
            return []
        }
        return [answer[start]] + answer[(start + 1)...].prefix { $0.hasPrefix("  ") }
    }
}
