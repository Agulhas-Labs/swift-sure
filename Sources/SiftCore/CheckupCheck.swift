//
// Copyright © Agulhas Labs
//

/// The six checks `checkup` runs, each named on exactly one of an answer's `checked:` and `not checked:` lists.
enum CheckupCheck: CaseIterable, Hashable, Sendable {
    case callers
    case testRuns
    case coverage
    case exposure
    case flakyTests
    case duplicates

    /// The name an answer spells it by.
    var name: String {
        switch self {
        case .callers: "callers"
        case .testRuns: "test runs"
        case .coverage: "changed-line coverage"
        case .exposure: "exposure"
        case .flakyTests: "flaky tests"
        case .duplicates: "duplicates"
        }
    }

    /// Whether it reads what `run` recorded, which is the working tree's content and no other revision's.
    var readsRecordedRuns: Bool {
        self == .testRuns || self == .coverage
    }

    /// Whether it reads the working tree itself, whatever revision the range ends at.
    var readsWorkingTree: Bool {
        switch self {
        case .callers, .exposure, .flakyTests, .duplicates: true
        case .testRuns, .coverage: false
        }
    }
}
