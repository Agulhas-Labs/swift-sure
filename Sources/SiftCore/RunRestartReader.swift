//
// Copyright © Agulhas Labs
//

import Foundation

/// Reads the restart markers of a log, taking from the outcomes read so far what each one interrupted.
struct RunRestartReader {
    private(set) var restarts: [RunRestart] = []
    private var named: Set<String> = []
    private var reportedBefore = 0
    private var xctestReportedBefore = 0
    /// How many lines have been fed, so a start and a trap can be ordered.
    private var position = 0
    /// Where each test's last start line sat.
    private var starts: [String: Int] = [:]
    /// The trap lines fed since the previous restart, each with where it sat.
    private var traps: [(line: String, position: Int)] = []

    /// Feeds one line, with the outcomes read up to and including it and the number of Swift Testing summaries already recorded.
    mutating func read(_ line: String, outcomes: RunTestOutcomes, summaries: Int) {
        position += 1
        guard RunRestart.isMarker(line) else {
            note(line)
            return
        }
        let open = outcomes.tallies.filter { name, tally in
            tally.started > tally.passed + tally.failed + tally.skipped && !named.contains(name)
        }.map(\.key).sorted()
        named.formUnion(open)
        let since = open.compactMap { starts[$0] }.min() ?? 0
        let ownTraps = traps.filter { $0.position > since }.map(\.line)
        traps = []
        let reported = Self.reported(in: outcomes)
        let xctestReported = Self.xctestReported(in: outcomes)
        restarts.append(RunRestart(
            open: open.map { outcomes.swiftTestingNames.contains($0) ? $0 : RunTestOutcomes.xctestDisplayName($0) },
            reported: reported - reportedBefore,
            summariesBefore: summaries,
            xctestReported: xctestReported - xctestReportedBefore,
            swiftTestingOpen: open.contains { outcomes.swiftTestingNames.contains($0) },
            xctestOpen: open.contains { !outcomes.swiftTestingNames.contains($0) },
            traps: ownTraps
        ))
        reportedBefore = reported
        xctestReportedBefore = xctestReported
    }

    /// Records where `line` starts a test, or keeps it where it is a trap line, which ``RunTestCrash/Reader`` reads only under `swift test`'s contract.
    private mutating func note(_ line: String) {
        if line.contains(" started"), let (name, event) = RunTestOutcomes.xctestEvent(in: line) ?? RunTestOutcomes.swiftTestingEvent(in: line), case .started = event {
            starts[name] = position
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if RunTestCrash.Reader.isTrap(trimmed) {
            traps.append((trimmed, position))
        }
    }

    /// How many Swift Testing tests have reported an ending in `outcomes`.
    static func reported(in outcomes: RunTestOutcomes) -> Int {
        outcomes.swiftTestingNames.reduce(0) { total, name in
            let tally = outcomes.tallies[name] ?? RunTestOutcomes.Tally()
            return total + tally.passed + tally.failed + tally.skipped
        }
    }

    /// How many XCTest tests have reported an ending in `outcomes`.
    static func xctestReported(in outcomes: RunTestOutcomes) -> Int {
        outcomes.tallies.filter { !outcomes.swiftTestingNames.contains($0.key) }.reduce(0) { $0 + $1.value.passed + $1.value.failed + $1.value.skipped }
    }
}
